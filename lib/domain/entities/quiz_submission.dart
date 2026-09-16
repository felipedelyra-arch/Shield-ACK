/// Entidades do quiz. Imutáveis, sem codegen: são estruturas que atravessam a
/// fronteira de domínio, não DTOs de JSON.
class QuizSubmission {
  const QuizSubmission({
    required this.lessonId,
    required this.answers,
    required this.clientElapsedMs,
  });

  final String lessonId;
  final List<QuizAnswer> answers;
  final int clientElapsedMs;
}

class QuizAnswer {
  /// [value] é `int` (múltipla escolha), `bool` (V/F), `List<int>`
  /// (ordenação/associação) ou `String` (preenchimento de terminal).
  /// O SERVIDOR valida o tipo contra o tipo da questão — o cliente não decide
  /// o que é válido.
  const QuizAnswer({required this.questionId, required this.value});

  final String questionId;
  final Object value;
}

class QuizOutcome {
  const QuizOutcome({
    required this.passed,
    required this.score,
    required this.correctCount,
    required this.total,
    required this.xpAwarded,
    required this.totalXp,
    required this.level,
    required this.hearts,
    required this.streakDays,
    required this.perQuestion,
    this.pending = false,
  });

  final bool passed;
  final double score;
  final int correctCount;
  final int total;
  final int xpAwarded;
  final int totalXp;
  final int level;
  final int hearts;
  final int streakDays;
  final List<QuestionFeedback> perQuestion;

  /// true = a submissão foi enfileirada e o resultado ainda não chegou do servidor.
  final bool pending;
}

class QuestionFeedback {
  const QuestionFeedback({
    required this.questionId,
    required this.correct,
    required this.explanation,
  });

  final String questionId;
  final bool correct;
  final String explanation;
}
