import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart';

import '../core/di/providers.dart';
import '../core/error/failure.dart';
import '../core/error/result.dart';
import '../domain/entities/learning.dart';
import '../domain/entities/quiz_submission.dart';
import '../domain/repositories/learning_repository.dart';
import '../domain/repositories/quiz_repository.dart';
import '../presentation/router.dart' show demoStateProvider;
import '../presentation/theme.dart';
import 'demo_state.dart';

/// Troca os repositórios do Firebase pelos da demo. Usado no `main` e nos testes.
List<Override> demoOverrides(DemoState demo) => [
      demoStateProvider.overrideWithValue(demo),
      authRepositoryProvider.overrideWithValue(DemoAuthRepository()),
      learningRepositoryProvider
          .overrideWithValue(DemoLearningRepository(demo)),
      quizRepositoryProvider.overrideWithValue(DemoQuizRepository(demo)),
    ];

class DemoAuthRepository implements AuthRepository {
  @override
  Stream<String?> watchUid() => Stream.value('demo');

  @override
  Future<Result<Failure, void>> signInWithGoogle() async => const Ok(null);

  @override
  Future<Result<Failure, void>> signInWithEmail(String e, String p) async =>
      const Ok(null);

  @override
  Future<Result<Failure, void>> signUpWithEmail(String e, String p) async =>
      const Ok(null);

  @override
  Future<void> signOut() async {}
}

/// Na demo o id da lição é o título.
DemoLesson _find(DemoState demo, String id) =>
    demo.tracks.expand((t) => t.lessons).firstWhere((l) => l.title == id);

/// Reemite a cada mudança do [DemoState] — o equivalente do listener do Firestore.
Stream<T> _watch<T>(ChangeNotifier source, T Function() read) {
  late final StreamController<T> c;
  void emit() => c.add(read());
  c = StreamController<T>(
    onListen: () {
      emit();
      source.addListener(emit);
    },
    onCancel: () => source.removeListener(emit),
  );
  return c.stream;
}

class DemoLearningRepository implements LearningRepository {
  DemoLearningRepository(this._demo);
  final DemoState _demo;

  @override
  Stream<Profile> watchProfile(String uid) => _watch(
        _demo,
        () => Profile(
          displayName: _demo.displayName,
          xp: _demo.xp,
          level: _demo.level,
          streakDays: _demo.streak,
          hearts: _demo.hearts,
          friendCode: _demo.friendCode,
        ),
      );

  @override
  Stream<List<Track>> watchTracks(String uid) => _watch(
        _demo,
        () => [
          for (final t in _demo.tracks)
            Track(
              id: t.title,
              title: t.title,
              blurb: t.blurb,
              lessons: [for (final l in t.lessons) _lesson(l)],
            ),
        ],
      );

  Lesson _lesson(DemoLesson l) => Lesson(
        id: l.title,
        title: l.title,
        durationSec: l.durationSec,
        xpReward: l.xpReward,
        resumeAtSec: l.resumeAtSec,
        status: switch (l.state) {
          Wire.ack => LessonStatus.completed,
          Wire.rst => LessonStatus.failed,
          Wire.syn when l.progress > 0 => LessonStatus.inProgress,
          Wire.syn => LessonStatus.available,
          Wire.idle => LessonStatus.locked,
        },
      );

  @override
  Future<Result<Failure, int>> startLesson(String lessonId) async =>
      Ok(_find(_demo, lessonId).resumeAtSec);

  @override
  Future<void> reportWatch(String lessonId, int positionSec, int _) async =>
      _demo.recordWatch(_find(_demo, lessonId), positionSec);
}

class DemoQuizRepository implements QuizRepository {
  DemoQuizRepository(this._demo);
  final DemoState _demo;

  @override
  Future<Result<Failure, List<Question>>> questions(String lessonId) async =>
      Ok([
        for (var i = 0; i < demoQuestions.length; i++)
          Question(
            id: 'q$i',
            type: QuestionType.single,
            prompt: demoQuestions[i].prompt,
            options: demoQuestions[i].options,
            code: demoQuestions[i].code,
          ),
      ]);

  /// Correção local. Só existe na demo — no app real o gabarito nunca chega ao aparelho.
  @override
  Future<Result<Failure, QuizOutcome>> submit(QuizSubmission s) async {
    final feedback = [
      for (final a in s.answers)
        () {
          final q = demoQuestions[int.parse(a.questionId.substring(1))];
          return QuestionFeedback(
            questionId: a.questionId,
            correct: a.value == q.correct,
            explanation: q.explanation,
          );
        }(),
    ];
    final correct = feedback.where((f) => f.correct).length;
    final xpBefore = _demo.xp;
    _demo.applyQuiz(
        lesson: _find(_demo, s.lessonId),
        correct: correct,
        total: s.answers.length);

    return Ok(QuizOutcome(
      passed: correct / s.answers.length >= 0.7,
      score: correct / s.answers.length,
      correctCount: correct,
      total: s.answers.length,
      xpAwarded: _demo.xp - xpBefore,
      totalXp: _demo.xp,
      level: _demo.level,
      hearts: _demo.hearts,
      streakDays: _demo.streak,
      perQuestion: feedback,
    ));
  }

  @override
  Future<QuizOutcome?> pendingOutcome(String idempotencyKey) async => null;
}
