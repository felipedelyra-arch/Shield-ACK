import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../demo/demo_state.dart';
import '../domain/entities/learning.dart';
import '../domain/entities/quiz_submission.dart';
import '../main.dart' show forcedLogoutProvider, isDemo;
import 'features/auth/pages/login_page.dart';
import 'features/lesson_player/pages/lesson_page.dart';
import 'features/quiz/pages/quiz_page.dart';
import 'features/quiz/pages/result_page.dart';
import 'shell.dart';

/// Router. O `redirect` é o único lugar que decide se uma rota é acessível —
/// espalhar checagem de auth pelas telas garante que uma delas será esquecida.
final routerProvider = Provider<GoRouter>((ref) {
  final demo = ref.watch(demoStateProvider);

  return GoRouter(
    initialLocation: isDemo ? '/' : '/login',
    // refreshListenable escuta auth E logout forçado: um token revogado pelo
    // servidor tira o usuário da tela sem depender de a tela perguntar.
    refreshListenable: _AuthRefresh(ref),
    redirect: (context, state) {
      // Em demo não há Firebase para consultar; o fluxo de login continua
      // navegável a partir de /login, só não é imposto.
      if (isDemo) return null;
      final user = FirebaseAuth.instance.currentUser;
      final loggingIn = state.matchedLocation == '/login';
      if (user == null) return loggingIn ? null : '/login';
      if (loggingIn) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => Shell(demo: demo)),
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(
        path: '/lesson',
        builder: (_, s) => LessonPage(lesson: s.extra! as Lesson),
      ),
      GoRoute(
        path: '/quiz',
        builder: (_, s) => QuizPage(lesson: s.extra! as Lesson),
      ),
      GoRoute(
        path: '/result',
        builder: (_, s) {
          final (lesson, questions, outcome) =
              s.extra! as (Lesson, List<Question>, QuizOutcome);
          return ResultPage(
              lesson: lesson, questions: questions, outcome: outcome);
        },
      ),
    ],
  );
});

/// Estado da demo. Trilha, aula e quiz já leem dos repositórios (core/di);
/// duelo e ranking ainda leem daqui.
final demoStateProvider = Provider((_) => DemoState());

class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    if (!isDemo) {
      FirebaseAuth.instance.authStateChanges().listen((_) => notifyListeners());
    }
    ref.read(forcedLogoutProvider).addListener(notifyListeners);
  }
}
