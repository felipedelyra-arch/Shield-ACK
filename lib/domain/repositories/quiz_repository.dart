import '../../core/error/failure.dart';
import '../../core/error/result.dart';
import '../entities/learning.dart';
import '../entities/quiz_submission.dart';

/// Abstração de domínio. Não conhece Firebase, drift nem Flutter — é o que permite
/// testar o usecase sem emulador. Verificado no CI por scripts/check_layering.sh.
abstract interface class QuizRepository {
  /// Questões da lição, SEM gabarito — ele nunca sai do servidor.
  Future<Result<Failure, List<Question>>> questions(String lessonId);

  Future<Result<Failure, QuizOutcome>> submit(QuizSubmission submission);

  /// Resultado de uma submissão que subiu depois (pela fila), para reconciliar a tela.
  Future<QuizOutcome?> pendingOutcome(String idempotencyKey);
}
