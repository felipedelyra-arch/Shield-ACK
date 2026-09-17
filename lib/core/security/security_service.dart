import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Guarda material criptográfico no Keystore (Android) / Keychain (iOS).
///
/// O que entra aqui: chave do banco local, chaves de sessão, flags de integridade.
/// O que NÃO entra: token do Firebase Auth — o SDK já o gerencia e duplicá-lo
/// significaria duas cópias do mesmo segredo, uma delas fora do ciclo de revogação.
class SecurityService {
  SecurityService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              // A partir do flutter_secure_storage 11 a criptografia deixou de ser
              // opt-in: `encryptedSharedPreferences` foi removido e o padrão passou a
              // ser AES-GCM com a chave embrulhada em RSA-OAEP no Keystore — mais
              // forte do que o antigo AES-CBC. `resetOnError: false` é deliberado:
              // apagar silenciosamente o material criptográfico ao primeiro erro de
              // leitura esconde adulteração. Preferimos falhar e disparar o wipe.
              aOptions: AndroidOptions(resetOnError: false),
              iOptions: IOSOptions(
                // first_unlock_this_device: legível após o primeiro desbloqueio, e
                // NÃO sobe para o backup do iCloud nem migra para outro aparelho.
                // `unlocked` quebraria background fetch; `always` sobe no backup.
                accessibility: KeychainAccessibility.first_unlock_this_device,
                synchronizable: false,
              ),
            );

  final FlutterSecureStorage _storage;

  static const _dbKeyAlias = 'shieldack.db.key.v1';
  static const _integrityAlias = 'shieldack.integrity.state.v1';

  /// Chave AES-256 do banco local (SQLCipher). [created] = acabou de ser gerada:
  /// um arquivo de banco que já exista foi cifrado com outra chave e é lixo.
  ///
  /// Gerada com [Random.secure] — CSPRNG do SO. `Random()` aqui seria uma
  /// vulnerabilidade real: PRNG previsível derruba a criptografia inteira do cache.
  Future<({Uint8List key, bool created})> databaseKey() async {
    final existing = await _storage.read(key: _dbKeyAlias);
    if (existing != null) {
      final bytes = base64Decode(existing);
      if (bytes.length == 32) {
        return (key: Uint8List.fromList(bytes), created: false);
      }
      // Tamanho errado = armazenamento corrompido ou adulterado: regenera, e o
      // chamador descarta o banco antigo.
    }

    final rnd = Random.secure();
    final key =
        Uint8List.fromList(List<int>.generate(32, (_) => rnd.nextInt(256)));
    await _storage.write(key: _dbKeyAlias, value: base64Encode(key));
    return (key: key, created: true);
  }

  Future<void> saveIntegrityState(String json) =>
      _storage.write(key: _integrityAlias, value: json);

  Future<String?> readIntegrityState() => _storage.read(key: _integrityAlias);

  /// Apaga TODO o material criptográfico.
  ///
  /// Chamado em: logout, falha de integridade (root/hook/repack), `id-token-revoked`.
  /// Apagar a chave do banco inutiliza o banco mesmo que o arquivo sobreviva —
  /// é mais rápido e mais confiável do que sobrescrever o arquivo.
  Future<void> wipeKeys() => _storage.deleteAll();
}
