import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Fila de ações de domínio pendentes de envio.
///
/// Por que uma tabela e não uma lista em SharedPreferences: precisamos de
/// transação (marcar enviado + gravar resposta atomicamente) e de query
/// por status ordenada. Ver docs/00-CORRECOES.md C4.
class OutboxItems extends Table {
  /// Chave de idempotência (UUID v4). É a MESMA enviada à Callable e usada como
  /// ID do documento em xpEvents — por isso é a PK aqui também.
  TextColumn get idempotencyKey => text()();

  /// Nome da Callable.
  TextColumn get operation => text()();

  /// Payload JSON.
  TextColumn get payload => text()();

  /// pending | inflight | done | dead
  TextColumn get status => text().withDefault(const Constant('pending'))();

  IntColumn get attempts => integer().withDefault(const Constant(0))();
  IntColumn get createdAtMs => integer()();
  IntColumn get nextAttemptAtMs => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  /// Resposta do servidor, para a UI reconciliar quando o item finalmente sobe.
  TextColumn get resultJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {idempotencyKey};
}

/// Cache do catálogo (documento agregado) — permite abrir o app offline.
class CachedCatalog extends Table {
  TextColumn get version => text()();
  TextColumn get json => text()();
  IntColumn get fetchedAtMs => integer()();

  @override
  Set<Column> get primaryKey => {version};
}

@DriftDatabase(tables: [OutboxItems, CachedCatalog])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  /// Abre o banco com SQLCipher usando a chave AES-256 do Keystore/Keychain.
  ///
  /// `PRAGMA key` PRECISA ser o primeiro comando da conexão — depois de qualquer
  /// outra instrução o SQLCipher já decidiu o modo e a chave é ignorada
  /// silenciosamente, deixando o banco EM CLARO. É o erro clássico de integração.
  static AppDatabase open(Uint8List key) {
    return AppDatabase(
      LazyDatabase(() async {
        final dir = await getApplicationDocumentsDirectory();
        final file = File(p.join(dir.path, 'shieldack.sqlite'));

        // Qual binário do SQLite é carregado vem de `hooks.user_defines.sqlite3`
        // no pubspec.yaml (`source: sqlcipher`), não de um override em Dart:
        // sqlcipher_flutter_libs foi descontinuado no sqlite3 3.x.
        final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

        return NativeDatabase(
          file,
          setup: (db) {
            db.execute("PRAGMA key = \"x'$hex'\";");
            // Prova que a chave funcionou. Sem esta linha, uma chave errada só
            // falharia na primeira query — depois do app já ter assumido sucesso.
            // Esta checagem carrega duas garantias:
            //  1. o binário carregado é mesmo o SQLCipher (e não o SQLite comum,
            //     caso o `source: sqlcipher` do pubspec não tenha sido aplicado);
            //  2. a chave foi aceita.
            // Sem ela, o `PRAGMA key` acima seria ignorado em silêncio e o banco
            // seria criado EM CLARO — o modo de falha mais perigoso possível aqui.
            final result = db.select('PRAGMA cipher_version;');
            if (result.isEmpty) {
              throw StateError(
                'SQLCipher indisponível: o banco seria criado em claro. '
                'Verifique hooks.user_defines.sqlite3.source: sqlcipher no pubspec.yaml.',
              );
            }
            db.execute('PRAGMA journal_mode = WAL;');
          },
        );
      }),
    );
  }

  Future<void> wipe() async {
    await transaction(() async {
      await delete(outboxItems).go();
      await delete(cachedCatalog).go();
    });
  }
}

/// Helper para (de)serializar payloads sem espalhar jsonEncode pelo código.
extension OutboxJson on OutboxItem {
  Map<String, dynamic> get payloadMap =>
      jsonDecode(payload) as Map<String, dynamic>;
  Map<String, dynamic>? get resultMap => resultJson == null
      ? null
      : jsonDecode(resultJson!) as Map<String, dynamic>;
}
