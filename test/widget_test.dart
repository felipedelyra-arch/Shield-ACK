import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shieldack/demo/demo_repositories.dart';
import 'package:shieldack/demo/demo_state.dart';
import 'package:shieldack/domain/entities/learning.dart';
import 'package:shieldack/domain/entities/quiz_submission.dart';
import 'package:shieldack/presentation/features/quiz/pages/quiz_page.dart';
import 'package:shieldack/presentation/features/quiz/pages/result_page.dart';
import 'package:shieldack/presentation/features/tracks/pages/tracks_page.dart';
import 'package:shieldack/presentation/theme.dart';

/// Smoke test do fluxo visível, com os repositórios da demo no lugar do Firebase:
/// as telas são as mesmas do app real, só a fonte dos dados muda.
///
/// Não testa pixel nem layout — testa que as REGRAS que a interface promete
/// continuam valendo. É o mínimo que falha se alguém quebrar a trilha.
Widget _app(DemoState demo, Widget home) => ProviderScope(
      overrides: demoOverrides(demo),
      child: MaterialApp(theme: buildTheme(), home: home),
    );

void main() {
  testWidgets('trilha lista as aulas e mostra o ponto de retomada',
      (tester) async {
    await tester.pumpWidget(_app(DemoState(), const TracksPage()));
    await tester.pumpAndSettle();

    expect(find.text('Handshake TCP: SYN, SYN-ACK, ACK'), findsOneWidget);
    // Aula em progresso mostra onde parou, não um rótulo genérico de estado.
    expect(find.textContaining('parou em'), findsOneWidget);
    // Aula bloqueada anuncia o custo, para dar motivo de seguir.
    expect(find.textContaining('XP'), findsWidgets);
  });

  testWidgets('aula bloqueada não é tocável', (tester) async {
    final demo = DemoState();
    final locked = demo.tracks.first.lessons.firstWhere((l) => l.locked);

    await tester.pumpWidget(_app(demo, const TracksPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text(locked.title));
    await tester.pumpAndSettle();
    // Sem navegação: continuamos na trilha.
    expect(find.text('Shield Ack'), findsOneWidget);
  });

  testWidgets('quiz só mostra acerto e explicação depois do envio',
      (tester) async {
    final demo = DemoState();
    final lesson = Lesson(
      id: demo.tracks.first.lessons[2].title,
      title: demo.tracks.first.lessons[2].title,
      durationSec: 738,
      xpReward: 40,
      status: LessonStatus.inProgress,
    );
    final router = GoRouter(
      initialLocation: '/quiz',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const SizedBox()),
        GoRoute(path: '/quiz', builder: (_, __) => QuizPage(lesson: lesson)),
        GoRoute(
          path: '/result',
          builder: (_, s) {
            final (l, qs, o) =
                s.extra! as (Lesson, List<Question>, QuizOutcome);
            return ResultPage(lesson: l, questions: qs, outcome: o);
          },
        ),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: demoOverrides(demo),
      child: MaterialApp.router(theme: buildTheme(), routerConfig: router),
    ));
    await tester.pumpAndSettle();

    for (final q in demoQuestions) {
      // Nada de gabarito antes do envio: a correção é do servidor.
      expect(find.text(q.explanation), findsNothing);
      expect(
          find.text(q == demoQuestions.last ? 'Enviar respostas' : 'Próxima'),
          findsOneWidget);
      await tester.tap(find.text(q.options[q.correct]));
      await tester.pump();
      await tester.tap(
          find.text(q == demoQuestions.last ? 'Enviar respostas' : 'Próxima'));
      await tester.pumpAndSettle();
    }

    expect(find.text('Conexão estabelecida'), findsOneWidget);
    // Explicação aparece mesmo no acerto: acertar por sorte e seguir é pior que errar.
    await tester.scrollUntilVisible(
        find.text(demoQuestions.first.explanation), 200);
    expect(find.text(demoQuestions.first.explanation), findsOneWidget);
    expect(demo.tracks.first.lessons[2].state, Wire.ack);
  });

  test('aprovar a lição credita XP e libera a próxima', () {
    final demo = DemoState();
    final lessons = demo.tracks.expand((t) => t.lessons).toList();
    final inProgress = lessons.firstWhere((l) => l.state == Wire.syn);
    final next = lessons[lessons.indexOf(inProgress) + 1];
    final xpBefore = demo.xp;

    demo.applyQuiz(lesson: inProgress, correct: 3, total: 3);

    expect(inProgress.state, Wire.ack);
    expect(demo.xp, greaterThan(xpBefore));
    expect(next.state, Wire.syn, reason: 'a próxima aula deve sair de travada');
  });

  test('reprovar consome vida e não credita XP', () {
    final demo = DemoState();
    final lesson =
        demo.tracks.first.lessons.firstWhere((l) => l.state == Wire.syn);
    final xpBefore = demo.xp;
    final heartsBefore = demo.hearts;

    demo.applyQuiz(lesson: lesson, correct: 1, total: 3);

    expect(lesson.state, Wire.rst);
    expect(demo.xp, xpBefore);
    expect(demo.hearts, heartsBefore - 1);
  });
}
