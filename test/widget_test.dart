import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shieldack/demo/demo_state.dart';
import 'package:shieldack/presentation/features/quiz/pages/quiz_page.dart';
import 'package:shieldack/presentation/features/tracks/pages/tracks_page.dart';
import 'package:shieldack/presentation/theme.dart';

/// Smoke test do fluxo visível: trilha desenha, lição travada não navega,
/// quiz corrige e o resultado altera o estado.
///
/// Não testa pixel nem layout — testa que as REGRAS que a interface promete
/// continuam valendo. É o mínimo que falha se alguém quebrar a trilha.
Widget _wrap(Widget child) => MaterialApp(theme: buildTheme(), home: child);

void main() {
  testWidgets('trilha lista as aulas e mostra o ponto de retomada',
      (tester) async {
    final demo = DemoState();
    await tester.pumpWidget(_wrap(TracksPage(demo: demo)));

    expect(find.text('Handshake TCP: SYN, SYN-ACK, ACK'), findsOneWidget);
    // Aula em progresso mostra onde parou, não um rótulo genérico de estado.
    expect(find.textContaining('parou em'), findsOneWidget);
    // Aula bloqueada anuncia o custo, para dar motivo de seguir.
    expect(find.textContaining('XP'), findsWidgets);
  });

  testWidgets('aula bloqueada não é tocável', (tester) async {
    final demo = DemoState();
    final locked = demo.tracks.first.lessons.firstWhere((l) => l.locked);
    expect(locked.locked, isTrue);

    await tester.pumpWidget(_wrap(TracksPage(demo: demo)));
    await tester.tap(find.text(locked.title));
    await tester.pump();
    // Sem navegação: continuamos na trilha.
    expect(find.text('Shield Ack'), findsOneWidget);
  });

  testWidgets('quiz revela explicação só depois de confirmar', (tester) async {
    final demo = DemoState();
    final lesson = demo.tracks.first.lessons.first;
    await tester.pumpWidget(_wrap(QuizPage(lesson: lesson, demo: demo)));

    final q = demoQuestions.first;
    expect(find.text(q.explanation), findsNothing);

    // Confirmar fica desabilitado até escolher.
    await tester.tap(find.text(q.options[q.correct]));
    await tester.pump();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();

    expect(find.text(q.explanation), findsOneWidget);
    // Explicação aparece mesmo no acerto: acertar por sorte e seguir é pior que errar.
    expect(find.text('Próxima'), findsOneWidget);
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
