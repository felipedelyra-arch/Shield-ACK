import '../../core/error/failure.dart';
import '../../core/error/result.dart';
import '../entities/quiz_submission.dart';

/// Abstração de domínio. Não conhece Firebase, drift nem Flutter — é o que permite
/// testar o usecase sem emulador. Verificado no CI por scripts/check_layering.sh.
abstract interface class QuizRepository {
  Future<Result<Failure, QuizOutcome>> submit(QuizSubmission submission);

  /// Resultado de uma submissão que subiu depois (pela fila), para reconciliar a tela.
  Future<QuizOutcome?> pendingOutcome(String idempotencyKey);
}
