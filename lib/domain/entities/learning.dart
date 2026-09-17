/// Entidades de trilha, perfil e questão. Sem Flutter e sem Firebase.
library;

enum LessonStatus { locked, available, inProgress, failed, completed }

class Lesson {
  const Lesson({
    required this.id,
    required this.title,
    required this.durationSec,
    required this.xpReward,
    required this.status,
    this.resumeAtSec = 0,
  });

  final String id;
  final String title;
  final int durationSec;
  final int xpReward;
  final LessonStatus status;
  final int resumeAtSec;

  bool get locked => status == LessonStatus.locked;
}

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.blurb,
    required this.lessons,
  });

  final String id;
  final String title;
  final String blurb;
  final List<Lesson> lessons;

  int get done =>
      lessons.where((l) => l.status == LessonStatus.completed).length;
}

class Profile {
  const Profile({
    required this.displayName,
    required this.xp,
    required this.level,
    required this.streakDays,
    required this.hearts,
    required this.friendCode,
  });

  final String displayName;
  final int xp;
  final int level;
  final int streakDays;
  final int hearts;
  final String friendCode;
}

/// Tipos que o servidor corrige (functions/src/lib/grading.ts).
enum QuestionType { single, boolean, order, match, fill }

class Question {
  const Question({
    required this.id,
    required this.type,
    required this.prompt,
    required this.options,
    this.prompts = const [],
    this.code,
  });

  final String id;
  final QuestionType type;
  final String prompt;

  /// single/boolean/order: alternativas. match: coluna da direita.
  final List<String> options;

  /// match: coluna da esquerda. A resposta é, para cada item, o índice da opção.
  final List<String> prompts;

  /// Trecho de terminal/protocolo mostrado acima da pergunta.
  final String? code;
}

/// Progresso de uma lição como o servidor grava em `users/{uid}/progress`.
class LessonProgress {
  const LessonProgress({
    required this.completed,
    required this.attempts,
    required this.lastPositionSec,
  });

  final bool completed;
  final int attempts;
  final int lastPositionSec;
}

/// Estado de cada lição de um módulo, na ordem.
///
/// Espelha o desbloqueio de `startLesson`: a primeira do módulo é livre, as demais
/// exigem a anterior concluída. É só desenho — quem autoriza é o servidor.
List<LessonStatus> resolveModule(List<LessonProgress?> progress) => [
      for (var i = 0; i < progress.length; i++)
        switch (progress[i]) {
          LessonProgress(completed: true) => LessonStatus.completed,
          LessonProgress(attempts: > 0) => LessonStatus.failed,
          LessonProgress() => LessonStatus.inProgress,
          null when i == 0 || progress[i - 1]?.completed == true =>
            LessonStatus.available,
          null => LessonStatus.locked,
        },
    ];

/// Vidas para exibição: o servidor grava (hearts, heartsUpdatedAt) e regenera
/// 1 a cada 30 min (functions/src/lib/hearts.ts). A verdade continua lá.
int displayHearts(int stored, DateTime? updatedAt, DateTime now) {
  const max = 5;
  if (stored >= max || updatedAt == null) return stored.clamp(0, max);
  final regen = now.difference(updatedAt).inMinutes ~/ 30;
  return (stored + (regen < 0 ? 0 : regen)).clamp(0, max);
}
