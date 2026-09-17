import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/di/providers.dart';
import 'core/firebase/firebase_bootstrap.dart';
import 'core/security/integrity_service.dart';
import 'core/security/security_service.dart';
import 'core/security/session_guard.dart';
import 'data/datasources/local/app_database.dart';
import 'data/datasources/local/outbox_worker.dart';
import 'app.dart';

/// Flavor injetado no build: --dart-define=SHIELDACK_ENV=prod
const _env = String.fromEnvironment('SHIELDACK_ENV', defaultValue: 'dev');
const isProd = _env == 'prod';

/// Modo de demonstração da interface: roda sem Firebase, com dados em memória.
///
/// Existe para dar para olhar as telas num aparelho antes de `flutterfire
/// configure`. Ele desliga App Check, Crashlytics, banco local e outbox — ou
/// seja, TODA a camada de segurança. O assert abaixo garante que ele não pode
/// coexistir com um build de produção.
const isDemo = _env == 'demo';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Trava dura: demo e prod são mutuamente exclusivos por construção.
  assert(!(isDemo && isProd),
      'SHIELDACK_ENV=demo nunca pode ser build de produção');

  if (isDemo) {
    // Só a interface. Nenhum Firebase, nenhum Keystore, nenhum banco.
    runApp(const ProviderScope(child: ShieldAckApp()));
    return;
  }

  await FirebaseBootstrap.init(isProd: isProd);

  // Chave do banco vem do Keystore/Keychain ANTES de qualquer abertura de banco.
  final security = SecurityService();
  final db = AppDatabase.open(await security.databaseKey());

  final integrity = IntegrityService(security);

  // SessionGuard precisa do container (para o token FCM) e o container precisa
  // do guard (para o logout forçado no FunctionsClient). O ciclo é quebrado com
  // um override preguiçoso: o provider só constrói o guard quando alguém o lê,
  // e nesse momento o container já existe.
  late final ProviderContainer container;
  container = ProviderContainer(overrides: [
    securityServiceProvider.overrideWithValue(security),
    appDatabaseProvider.overrideWithValue(db),
    integrityServiceProvider.overrideWithValue(integrity),
    sessionGuardProvider.overrideWith((ref) => SessionGuard(
          auth: FirebaseAuth.instance,
          security: security,
          db: db,
          integrity: integrity,
          clearFcmToken: () => ref.read(fcmProvider).deleteToken(),
          onForcedLogout: () => container.read(forcedLogoutProvider).value++,
        )),
  ]);

  container.read(sessionGuardProvider).start();

  // Sem cascade aqui: `..onX = (a) => expr` faz o `..` seguinte ser absorvido
  // pelo corpo da arrow function, e o segundo setter passa a ser aplicado ao
  // retorno do lambda em vez de ao objeto.
  integrity.onActiveAttack =
      (reason) => container.read(sessionGuardProvider).forceLogout(reason);
  // Telemetria vai para o Crashlytics como custom key, nunca para o log em prod.
  integrity.onTelemetry = (threat, severity) =>
      FirebaseCrashlytics.instance.setCustomKey('integrity_$threat', severity);

  if (isProd) {
    await integrity.start(
      androidPackageName: 'br.com.shieldack.app',
      androidSigningHash: const String.fromEnvironment('ANDROID_SIGNING_HASH'),
      iosBundleId: 'br.com.shieldack.app',
      iosTeamId: const String.fromEnvironment('IOS_TEAM_ID'),
      watcherMail: 'security@shieldack.com.br',
    );
  }

  container.read(outboxProvider).start();
  await registerOutboxWorker();

  runApp(UncontrolledProviderScope(
      container: container, child: const ShieldAckApp()));
}

/// Sinaliza logout forçado; o router escuta e volta para a tela de login.
///
/// Um `ValueNotifier` em vez do `StateProvider` do Riverpod 2 (removido do import
/// principal no Riverpod 3): o `refreshListenable` do go_router já quer um
/// `Listenable`, então isto é um adaptador a menos.
final forcedLogoutProvider = Provider((_) => ValueNotifier<int>(0));
