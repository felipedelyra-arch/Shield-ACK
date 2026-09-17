import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/local/app_database.dart';
import '../../data/datasources/local/outbox.dart';
import '../../data/repositories/firebase_auth_repository.dart';
import '../../data/repositories/firebase_learning_repository.dart';
import '../../data/repositories/quiz_repository_impl.dart';
import '../../domain/entities/learning.dart';
import '../../domain/repositories/learning_repository.dart';
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

// Repositórios. O modo demo sobrescreve os três (lib/demo/demo_repositories.dart);
// as telas só conhecem as interfaces de domain/.

final quizRepositoryProvider = Provider<QuizRepository>((ref) =>
    QuizRepositoryImpl(ref.watch(outboxProvider), FirebaseFirestore.instance));

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  const serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
  return FirebaseAuthRepository(
    FirebaseAuth.instance,
    wipeSession: () =>
        ref.read(sessionGuardProvider).forceLogout('user_logout'),
    googleServerClientId: serverClientId.isEmpty ? null : serverClientId,
  );
});

final learningRepositoryProvider =
    Provider<LearningRepository>((ref) => FirebaseLearningRepository(
          db: FirebaseFirestore.instance,
          functions: ref.watch(functionsClientProvider),
          outbox: ref.watch(outboxProvider),
          catalogVersion:
              FirebaseRemoteConfig.instance.getString('catalog_version'),
        ));

final uidProvider = StreamProvider<String?>(
    (ref) => ref.watch(authRepositoryProvider).watchUid());

// Dependem do uid: trocar de conta recria os streams em vez de mostrar dados da anterior.

final profileProvider = StreamProvider<Profile>((ref) {
  final uid = ref.watch(uidProvider).value;
  return uid == null
      ? const Stream.empty()
      : ref.watch(learningRepositoryProvider).watchProfile(uid);
});

final tracksProvider = StreamProvider<List<Track>>((ref) {
  final uid = ref.watch(uidProvider).value;
  return uid == null
      ? const Stream.empty()
      : ref.watch(learningRepositoryProvider).watchTracks(uid);
});

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
