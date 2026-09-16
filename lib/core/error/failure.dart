/// Falha de domínio. É isto que a UI vê — nunca uma [FirebaseException].
///
/// A tradução acontece no datasource (`core/firebase/functions_client.dart`).
/// Se um `FirebaseException` chegar na apresentação, é bug de arquitetura.
///
/// **Sem freezed de propósito.** O Dart 3 tem `sealed class` nativo e o
/// compilador já verifica a exaustividade do `switch` sobre a hierarquia —
/// que é a única coisa que o freezed acrescentaria aqui. freezed continua no
/// projeto para os DTOs de `data/models/`, onde `json_serializable` realmente
/// paga o custo do codegen.
sealed class Failure {
  const Failure();
}

/// Sem rede. A ação foi para o outbox e será reenviada.
final class OfflineFailure extends Failure {
  const OfflineFailure({this.queued = true});
  final bool queued;
}

final class UnauthenticatedFailure extends Failure {
  const UnauthenticatedFailure();
}

/// ID token revogado no servidor (logout global / comprometimento).
/// A UI deve forçar logout e limpar o armazenamento local.
final class SessionRevokedFailure extends Failure {
  const SessionRevokedFailure();
}

final class EmailNotVerifiedFailure extends Failure {
  const EmailNotVerifiedFailure();
}

/// App Check recusou o cliente: binário adulterado, emulador, ou device sem
/// Play Services / App Attest.
final class IntegrityRejectedFailure extends Failure {
  const IntegrityRejectedFailure();
}

final class RateLimitedFailure extends Failure {
  const RateLimitedFailure(this.retryAfterSec);
  final int retryAfterSec;
}

/// Regra de negócio do servidor: `LESSON_LOCKED`, `NO_HEARTS`, `NOT_FRIENDS`.
final class DeniedFailure extends Failure {
  const DeniedFailure(this.code);
  final String code;
}

final class NotFoundFailure extends Failure {
  const NotFoundFailure();
}

final class ConflictFailure extends Failure {
  const ConflictFailure(this.code);
  final String code;
}

final class InvalidInputFailure extends Failure {
  const InvalidInputFailure(this.code);
  final String code;
}

/// Bucket final. `detail` vai só para o Crashlytics, nunca para a tela.
final class UnexpectedFailure extends Failure {
  const UnexpectedFailure(this.detail);
  final String detail;
}
