import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/failure.dart';
import '../../../core/firebase/functions_client.dart';
import 'app_database.dart';

/// Fila persistente de escritas de domínio.
///
/// **Por que ela existe:** `cloud_firestore` enfileira writes offline nativamente;
/// `cloud_functions` NÃO. Como a regra de ouro manda toda escrita de domínio passar
/// por Callable, perdemos a fila nativa. O outbox devolve essa garantia.
///
/// **Garantia oferecida:** at-least-once. A exatidão vem da idempotência do
/// servidor (eventId == idempotencyKey), não da fila. Uma fila exactly-once no
/// cliente é impossível — o app pode morrer entre o commit do servidor e o ack.
class Outbox {
  Outbox(this._db, this._client, {Duration? tickInterval})
      : _tick = tickInterval ?? const Duration(seconds: 5);

  final AppDatabase _db;
  final FunctionsClient _client;
  final Duration _tick;
  final _uuid = const Uuid();
  final _rnd = Random();

  Timer? _timer;

  /// Drenagem em curso, ou null. Guardamos o FUTURE, não um bool: um chamador que
  /// dá `await drain()` durante outra drenagem precisa esperar o trabalho terminar,
  /// não receber um "pronto" imediato e falso.
  Future<void>? _inFlight;

  /// Backoff exponencial com JITTER.
  ///
  /// O jitter não é detalhe: sem ele, 10 mil dispositivos que perderam a rede no
  /// mesmo instante voltam a chamar no mesmo instante — thundering herd que derruba
  /// justamente o backend que acabou de se recuperar.
  Duration _backoff(int attempt) {
    final base = min(300, pow(2, attempt).toInt() * 2); // 2,4,8,…,300s
    final jitter = _rnd.nextInt(max(1, base ~/ 2));
    return Duration(seconds: base + jitter);
  }

  static const _maxAttempts = 8;

  /// Enfileira uma ação. Devolve a chave de idempotência para a UI correlacionar.
  Future<String> enqueue(String operation, Map<String, dynamic> payload) async {
    final key = _uuid.v4();
    await _db.into(_db.outboxItems).insert(
          OutboxItemsCompanion.insert(
            idempotencyKey: key,
            operation: operation,
            // A chave vai DENTRO do payload: é ela que o servidor usa como ID do
            // documento de XP. Gerar no cliente é o que torna o retry seguro.
            payload: jsonEncode({...payload, 'idempotencyKey': key}),
            createdAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    unawaited(drain());
    return key;
  }

  void start() {
    _timer ??= Timer.periodic(_tick, (_) => unawaited(drain()));
    unawaited(drain());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Processa a fila.
  ///
  /// Reentrante-safe por COALESCÊNCIA: chamadas concorrentes compartilham a mesma
  /// drenagem em vez de virar no-op. Sem isso, `await drain()` logo depois de um
  /// `enqueue()` (que dispara drenagem sem esperar) retornaria antes de o item ter
  /// sido enviado — bug silencioso em produção e teste intermitente.
  Future<void> drain() => _inFlight ??= _drain().whenComplete(() => _inFlight = null);

  Future<void> _drain() async {
    final now = DateTime.now().millisecondsSinceEpoch;

    final due = await (_db.select(_db.outboxItems)
          ..where((t) => t.status.isIn(['pending', 'inflight']))
          ..where((t) => t.nextAttemptAtMs.isSmallerOrEqualValue(now))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAtMs)])
          ..limit(20))
        .get();

    for (final item in due) {
      // 'inflight' sinaliza "enviei e não sei o resultado". No próximo boot ele
      // é reenviado — e o servidor devolve o resultado gravado via outboxAck,
      // sem reprocessar. É esta combinação que fecha o buraco do "app morto no
      // meio da submissão".
      await (_db.update(_db.outboxItems)..where((t) => t.idempotencyKey.equals(item.idempotencyKey)))
          .write(const OutboxItemsCompanion(status: Value('inflight')));

      final result = await _client.call(item.operation, item.payloadMap);

      await result.fold(
        (failure) => _onFailure(item, failure),
        (data) => _onSuccess(item, data),
      );
    }
  }

  Future<void> _onSuccess(OutboxItem item, Map<String, dynamic> data) async {
    await (_db.update(_db.outboxItems)..where((t) => t.idempotencyKey.equals(item.idempotencyKey)))
        .write(OutboxItemsCompanion(
      status: const Value('done'),
      resultJson: Value(jsonEncode(data)),
    ));
  }

  Future<void> _onFailure(OutboxItem item, Failure failure) async {
    final attempts = item.attempts + 1;

    // Falha PERMANENTE não entra em retry: reenviar um payload inválido oito vezes
    // só queima bateria e cota. Vai para 'dead' e a UI mostra o item com erro.
    final permanent = switch (failure) {
      InvalidInputFailure() => true,
      DeniedFailure() => true,
      NotFoundFailure() => true,
      ConflictFailure() => true,
      EmailNotVerifiedFailure() => true,
      _ => false,
    };

    // RateLimited respeita o retryAfter do servidor em vez do backoff local.
    final delay = switch (failure) {
      RateLimitedFailure(:final retryAfterSec) => Duration(seconds: retryAfterSec),
      _ => _backoff(attempts),
    };

    await (_db.update(_db.outboxItems)..where((t) => t.idempotencyKey.equals(item.idempotencyKey)))
        .write(OutboxItemsCompanion(
      status: Value(permanent || attempts >= _maxAttempts ? 'dead' : 'pending'),
      attempts: Value(attempts),
      nextAttemptAtMs: Value(DateTime.now().add(delay).millisecondsSinceEpoch),
      lastError: Value(failure.runtimeType.toString()),
    ));
  }

  /// Itens ainda não confirmados — a UI usa isto para mostrar "sincronizando".
  Stream<int> watchPending() => (_db.selectOnly(_db.outboxItems)
        ..addColumns([_db.outboxItems.idempotencyKey.count()])
        ..where(_db.outboxItems.status.isIn(['pending', 'inflight'])))
      .map((r) => r.read(_db.outboxItems.idempotencyKey.count()) ?? 0)
      .watchSingle();

  /// Resultado já sincronizado de uma ação — usado para reconciliar a tela de quiz
  /// quando o envio só subiu depois que o usuário saiu da tela.
  Future<Map<String, dynamic>?> resultFor(String idempotencyKey) async {
    final row = await (_db.select(_db.outboxItems)
          ..where((t) => t.idempotencyKey.equals(idempotencyKey)))
        .getSingleOrNull();
    return row?.resultMap;
  }

  /// Limpeza: itens concluídos há mais de 7 dias não servem para nada.
  Future<void> vacuum() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    await (_db.delete(_db.outboxItems)
          ..where((t) => t.status.equals('done') & t.createdAtMs.isSmallerThanValue(cutoff)))
        .go();
  }
}
