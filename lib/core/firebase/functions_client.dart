import 'dart:async';
import 'dart:io';

// cloud_functions exporta um `Result` próprio que colide com o nosso Result
// algébrico. `hide` é preferível a prefixar: o tipo que queremos aqui é o nosso.
import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:firebase_auth/firebase_auth.dart';

import '../error/failure.dart';
import '../error/result.dart';

/// Único ponto de chamada de Cloud Functions no app.
///
/// Responsabilidades:
///  - traduzir [FirebaseFunctionsException] em [Failure] (a UI nunca vê exceção do SDK);
///  - detectar `id-token-revoked` e disparar logout forçado;
///  - timeout explícito (o default do SDK é 60s — tempo demais para uma UI).
///
/// NÃO faz retry. Retry é responsabilidade do outbox, que tem estado persistente
/// e backoff; um retry aqui duplicaria tentativas e ignoraria a idempotencyKey.
class FunctionsClient {
  FunctionsClient({
    required FirebaseFunctions functions,
    required FirebaseAuth auth,
    required Future<void> Function(String reason) onSessionRevoked,
  })  : _functions = functions,
        _auth = auth,
        _onSessionRevoked = onSessionRevoked;

  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;
  final Future<void> Function(String reason) _onSessionRevoked;

  static const _timeout = Duration(seconds: 20);

  Future<Result<Failure, Map<String, dynamic>>> call(
    String name,
    Map<String, dynamic> payload,
  ) async {
    try {
      // Força revalidação do token se ele estiver perto de expirar. Sem isto,
      // a Callable falha com unauthenticated e o usuário vê erro em vez de refresh.
      await _auth.currentUser?.getIdToken();

      final res = await _functions
          .httpsCallable(name, options: HttpsCallableOptions(timeout: _timeout))
          .call<Map<Object?, Object?>>(payload);

      return Ok(Map<String, dynamic>.from(res.data));
    } on FirebaseFunctionsException catch (e) {
      return Err(_mapFunctionsError(e));
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-token-expired' || e.code == 'user-disabled') {
        await _onSessionRevoked(e.code);
        return const Err(SessionRevokedFailure());
      }
      return const Err(UnauthenticatedFailure());
    } on SocketException {
      return const Err(OfflineFailure());
    } on TimeoutException {
      return const Err(OfflineFailure());
    } catch (e) {
      return Err(UnexpectedFailure(e.runtimeType.toString()));
    }
  }

  Failure _mapFunctionsError(FirebaseFunctionsException e) {
    // `message` carrega o código do contrato (ver functions/src/lib/errors.ts).
    final code = e.message ?? '';

    switch (e.code) {
      case 'unauthenticated':
        unawaited(_onSessionRevoked('unauthenticated'));
        return const UnauthenticatedFailure();

      case 'failed-precondition':
        if (code == 'APP_CHECK_REQUIRED') {
          return const IntegrityRejectedFailure();
        }
        if (code == 'EMAIL_NOT_VERIFIED') {
          return const EmailNotVerifiedFailure();
        }
        return DeniedFailure(code);

      case 'resource-exhausted':
        final retry = (e.details as Map?)?['retryAfterSec'];
        return RateLimitedFailure(retry is int ? retry : 60);

      case 'permission-denied':
        return DeniedFailure(code);

      case 'not-found':
        return const NotFoundFailure();

      case 'aborted':
        return ConflictFailure(code);

      case 'invalid-argument':
        return InvalidInputFailure(code);

      case 'unavailable':
      case 'deadline-exceeded':
        // Servidor indisponível é indistinguível de offline do ponto de vista do
        // outbox: em ambos o item deve permanecer na fila.
        return const OfflineFailure();

      default:
        return UnexpectedFailure('${e.code}:$code');
    }
  }
}
