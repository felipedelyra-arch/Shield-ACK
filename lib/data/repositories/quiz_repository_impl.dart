import '../../core/error/failure.dart';
import '../../core/error/result.dart';
import '../../domain/entities/quiz_submission.dart';
import '../../domain/repositories/quiz_repository.dart';
import '../datasources/local/outbox.dart';

class QuizRepositoryImpl implements QuizRepository {
  QuizRepositoryImpl(this._outbox);

  final Outbox _outbox;

  /// Submissão SEMPRE passa pelo outbox — inclusive online.
  ///
  /// Caminho único: um "chama direto se online, enfileira se offline" cria dois
  /// fluxos, dois conjuntos de bugs, e uma janela em que a rede cai entre a
  /// checagem e a chamada. Com caminho único, o teste de modo avião testa o
  /// mesmo código que roda em 5G.
  @override
  Future<Result<Failure, QuizOutcome>> submit(QuizSubmission s) async {
    final key = await _outbox.enqueue('submitQuiz', {
      'lessonId': s.lessonId,
      'clientElapsedMs': s.clientElapsedMs,
      'answers': s.answers
          .map((a) => {'questionId': a.questionId, 'value': a.value})
          .toList(growable: false),
    });

    // A fila já tentou drenar em `enqueue`. Se o resultado chegou, devolvemos o
    // real; se não, devolvemos um outcome `pending` e a tela mostra "sincronizando".
    final data = await _outbox.resultFor(key);
    if (data == null) {
      return Ok(QuizOutcome(
        passed: false,
        score: 0,
        correctCount: 0,
        total: s.answers.length,
        xpAwarded: 0,
        totalXp: 0,
        level: 0,
        hearts: 0,
        streakDays: 0,
        perQuestion: const [],
        pending: true,
      ));
    }
    return Ok(_map(data));
  }

  @override
  Future<QuizOutcome?> pendingOutcome(String idempotencyKey) async {
    final data = await _outbox.resultFor(idempotencyKey);
    return data == null ? null : _map(data);
  }

  QuizOutcome _map(Map<String, dynamic> d) => QuizOutcome(
        passed: d['passed'] as bool,
        score: (d['score'] as num).toDouble(),
        correctCount: d['correctCount'] as int,
        total: d['total'] as int,
        xpAwarded: d['xpAwarded'] as int,
        totalXp: d['totalXp'] as int,
        level: d['level'] as int,
        hearts: d['hearts'] as int,
        streakDays: d['streakDays'] as int,
        perQuestion: (d['perQuestion'] as List)
            .map((e) => QuestionFeedback(
                  questionId: e['questionId'] as String,
                  correct: e['correct'] as bool,
                  explanation: (e['explanation'] as String?) ?? '',
                ))
            .toList(growable: false),
      );
}
