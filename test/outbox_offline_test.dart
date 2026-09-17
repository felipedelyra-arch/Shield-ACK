import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shieldack/core/error/failure.dart';
import 'package:shieldack/core/error/result.dart';
import 'package:shieldack/core/firebase/functions_client.dart';
import 'package:shieldack/data/datasources/local/app_database.dart';
import 'package:shieldack/data/datasources/local/outbox.dart';

/// Cenários offline obrigatórios (docs/06-operacao.md §6.4).
///
/// Usa banco em memória e um FunctionsClient falso: o objetivo é provar o
/// COMPORTAMENTO DA FILA, não a rede. Os testes de rede real ficam na suíte
/// de integração com o Firebase Emulator.
class _FakeClient implements FunctionsClient {
  _FakeClient(this.responder);
  final Future<Result<Failure, Map<String, dynamic>>> Function(
      String, Map<String, dynamic>) responder;

  final calls = <({String op, Map<String, dynamic> payload})>[];

  @override
  Future<Result<Failure, Map<String, dynamic>>> call(
      String name, Map<String, dynamic> payload) {
    calls.add((op: name, payload: payload));
    return responder(name, payload);
  }

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('modo avião: item fica pendente e sobe quando a rede volta', () async {
    var online = false;
    final client = _FakeClient((_, __) async => online
        ? const Ok({'passed': true, 'xpAwarded': 20})
        : const Err(OfflineFailure()));

    final outbox = Outbox(db, client);
    final key = await outbox.enqueue('submitQuiz', {'lessonId': 'l1'});

    expect(await outbox.resultFor(key), isNull,
        reason: 'offline: sem resultado ainda');
    expect(await outbox.watchPending().first, 1);

    online = true;
    // nextAttemptAtMs foi empurrado pelo backoff; forçamos a elegibilidade.
    await db.customStatement('UPDATE outbox_items SET next_attempt_at_ms = 0');
    await outbox.drain();

    expect((await outbox.resultFor(key))?['xpAwarded'], 20);
    expect(await outbox.watchPending().first, 0);
  });

  test('a idempotencyKey vai no payload e é ESTÁVEL entre tentativas',
      () async {
    var attempts = 0;
    final client = _FakeClient((_, __) async {
      attempts++;
      return attempts < 3
          ? const Err(OfflineFailure())
          : const Ok({'ok': true});
    });

    final outbox = Outbox(db, client);
    final key = await outbox.enqueue('submitQuiz', {'lessonId': 'l1'});

    for (var i = 0; i < 3; i++) {
      await db
          .customStatement('UPDATE outbox_items SET next_attempt_at_ms = 0');
      await outbox.drain();
    }

    // É ISTO que impede XP duplicado: o servidor vê sempre a mesma chave.
    final keys = client.calls.map((c) => c.payload['idempotencyKey']).toSet();
    expect(keys, {key}, reason: 'a chave não pode mudar entre retries');
    expect(client.calls.length, greaterThanOrEqualTo(3),
        reason: 'a drenagem disparada pelo enqueue coalesce com as do teste');
  });

  test('falha PERMANENTE não entra em retry — vai direto para dead', () async {
    final client = _FakeClient(
        (_, __) async => const Err(InvalidInputFailure('INVALID_LESSONID')));
    final outbox = Outbox(db, client);
    await outbox.enqueue('submitQuiz', {'lessonId': '../../answerKeys'});

    await db.customStatement('UPDATE outbox_items SET next_attempt_at_ms = 0');
    await outbox.drain();

    expect(client.calls.length, 1,
        reason: 'payload inválido não deve ser reenviado');
    final row = await db.select(db.outboxItems).getSingle();
    expect(row.status, 'dead');
  });

  test('rate limit respeita o retryAfter do servidor, não o backoff local',
      () async {
    final client =
        _FakeClient((_, __) async => const Err(RateLimitedFailure(900)));
    final outbox = Outbox(db, client);
    await outbox.enqueue('submitQuiz', {'lessonId': 'l1'});
    await db.customStatement('UPDATE outbox_items SET next_attempt_at_ms = 0');
    await outbox.drain();

    final row = await db.select(db.outboxItems).getSingle();
    final waitMs = row.nextAttemptAtMs - DateTime.now().millisecondsSinceEpoch;
    expect(waitMs, greaterThan(800 * 1000));
  });

  test('app encerrado no meio do envio: item inflight é reenviado no boot',
      () async {
    final client = _FakeClient((_, __) async => const Ok({'replayed': true}));
    final outbox = Outbox(db, client);
    final key = await outbox.enqueue('x', {});

    // Simula morte do processo com o item marcado como enviado-sem-resposta.
    await db.customStatement(
        "UPDATE outbox_items SET status = 'inflight', next_attempt_at_ms = 0");

    await Outbox(db, client).drain(); // "novo boot"
    expect((await outbox.resultFor(key))?['replayed'], true);
  });
}
