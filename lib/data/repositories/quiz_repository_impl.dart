import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/error/failure.dart';
import '../../core/error/result.dart';
import '../../domain/entities/learning.dart';
import '../../domain/entities/quiz_submission.dart';
import '../../domain/repositories/quiz_repository.dart';
import '../datasources/local/app_database.dart';
import '../datasources/local/outbox.dart';
import 'firestore_failure.dart';

class QuizRepositoryImpl implements QuizRepository {
  QuizRepositoryImpl(this._outbox, this._db);

  final Outbox _outbox;
  final FirebaseFirestore _db;

  @override
  Future<Result<Failure, List<Question>>> questions(String lessonId) =>
      guardFirestore(() async {
        // Sem orderBy: ele esconderia questões sem `order`, e o servidor recusa
        // submissão que não responde todas (INCOMPLETE_ANSWERS).
        final snap =
            await _db.collection('lessons/$lessonId/questions').limit(20).get();
        final docs = [...snap.docs]..sort((a, b) =>
            ((a.data()['order'] as int?) ?? 0)
                .compareTo((b.data()['order'] as int?) ?? 0));
        return docs.map(_question).toList(growable: false);
      });

  Question _question(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final type = QuestionType.values.asNameMap()[m['type']];
    // Tipo desconhecido não pode ser pulado: a lição ficaria impossível de enviar.
    if (type == null) throw StateError('question_type:${m['type']}');
    return Question(
      id: d.id,
      type: type,
      prompt: m['prompt'] as String,
      options: List<String>.from(m['options'] as List? ?? const []),
      prompts: List<String>.from(m['prompts'] as List? ?? const []),
      code: m['code'] as String?,
    );
  }

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

    // Espera a tentativa imediata: `enqueue` só a dispara, e `drain` coalesce com ela.
    await _outbox.drain();
    final item = await _outbox.find(key);

    return switch (item?.status) {
      'done' => Ok(_map(item!.resultMap!)),
      // Recusa definitiva do servidor (NO_HEARTS, LESSON_LOCKED…): não adianta esperar.
      'dead' => Err(DeniedFailure(item!.lastError ?? '')),
      // Sem rede: ficou na fila e sobe sozinho.
      _ => Ok(QuizOutcome(
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
        )),
    };
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
