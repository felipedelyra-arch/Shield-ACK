import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/local/app_database.dart';
import '../../data/datasources/local/outbox.dart';
import '../../data/repositories/quiz_repository_impl.dart';
import '../../domain/repositories/quiz_repository.dart';
import '../firebase/functions_client.dart';
import '../security/integrity_service.dart';
import '../security/security_service.dart';
import '../security/session_guard.dart';

/// Região das Functions. Deve bater com REGION em functions/src/lib/init.ts —
/// chamar a região errada é um 404 silencioso que custa uma tarde de debug.
const functionsRegion = 'southamerica-east1';

final securityServiceProvider = Provider((_) => SecurityService());

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('sobrescrito no bootstrap com a chave do Keystore');
});

final integrityServiceProvider = Provider(
  (ref) => IntegrityService(ref.watch(securityServiceProvider)),
);

final sessionGuardProvider = Provider<SessionGuard>((ref) {
  throw UnimplementedError('sobrescrito no bootstrap');
});

final functionsClientProvider = Provider((ref) => FunctionsClient(
      functions: FirebaseFunctions.instanceFor(region: functionsRegion),
      auth: FirebaseAuth.instance,
      onSessionRevoked: (reason) =>
          ref.read(sessionGuardProvider).forceLogout(reason),
    ));

final outboxProvider = Provider<Outbox>((ref) {
  final outbox = Outbox(
      ref.watch(appDatabaseProvider), ref.watch(functionsClientProvider));
  // onDispose sempre: um Timer sobrevivente é bateria e cota queimadas em silêncio.
  ref.onDispose(outbox.stop);
  return outbox;
});

final quizRepositoryProvider = Provider<QuizRepository>(
    (ref) => QuizRepositoryImpl(ref.watch(outboxProvider)));

/// Container mínimo para o isolate do WorkManager (sem UI, sem listeners).
Future<ProviderContainer> buildHeadlessContainer() async {
  final security = SecurityService();
  final db = AppDatabase.open(await security.databaseKey());
  return ProviderContainer(overrides: [
    securityServiceProvider.overrideWithValue(security),
    appDatabaseProvider.overrideWithValue(db),
    // No isolate headless não há UI para deslogar; revogação é tratada no próximo
    // foreground pelo SessionGuard.
    sessionGuardProvider.overrideWith((ref) => throw UnimplementedError()),
    functionsClientProvider.overrideWith((ref) => FunctionsClient(
          functions: FirebaseFunctions.instanceFor(region: functionsRegion),
          auth: FirebaseAuth.instance,
          onSessionRevoked: (_) async {},
        )),
  ]);
}

final fcmProvider = Provider((_) => FirebaseMessaging.instance);
