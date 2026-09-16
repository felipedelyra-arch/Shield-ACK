import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';

/// Inicialização do Firebase. Ordem importa.
class FirebaseBootstrap {
  static Future<void> init({required bool isProd}) async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    // --- App Check ANTES de qualquer outro SDK fazer request.
    //
    // É ele — não o SSL pinning, não a ofuscação — que impede um cliente não
    // autêntico (script curl, app repackaged, emulador) de falar com o backend.
    // Play Integrity e App Attest atestam no SERVIDOR do Google; o atacante não
    // controla essa checagem, diferente de qualquer detecção feita dentro do app.
    await FirebaseAppCheck.instance.activate(
      providerAndroid:
          isProd ? const AndroidPlayIntegrityProvider() : const AndroidDebugProvider(),
      // appAttest puro, sem fallback para DeviceCheck: o fallback aceita devices que
      // não suportam App Attest (iOS < 14), e é justamente esse conjunto que um
      // atacante escolheria emular. Preferimos recusar o device antigo.
      providerApple: isProd ? const AppleAppAttestProvider() : const AppleDebugProvider(),
    );
    // Token de App Check renovado automaticamente enquanto o app está em foreground.
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);

    // --- Persistência offline do Firestore.
    //
    // Resolve LEITURA offline e cache. NÃO resolve escrita de domínio, porque
    // toda escrita passa por Callable, que não tem fila offline nativa —
    // esse buraco é tapado pelo outbox (lib/data/datasources/local/outbox.dart).
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      // Cache ilimitado enche o disco do usuário e guarda dados do usuário num
      // dispositivo que tratamos como hostil. 40MB cobre catálogo + progresso.
      cacheSizeBytes: 40 * 1024 * 1024,
    );

    // --- Crashlytics captura tudo, inclusive erro fora da zona do Flutter.
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(isProd);

    // --- Remote Config: feature flags e parâmetros de gamificação.
    final rc = FirebaseRemoteConfig.instance;
    await rc.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 10),
      minimumFetchInterval: const Duration(hours: 1),
    ));
    await rc.setDefaults(remoteConfigDefaults);
    unawaited(rc.fetchAndActivate()); // não bloqueia o boot
  }
}

/// Defaults do Remote Config. Todo parâmetro de gamificação e toda feature do
/// roadmap tem flag aqui — ligar uma feature vira mudança de configuração, não release.
const remoteConfigDefaults = <String, dynamic>{
  // Catálogo: versão do documento agregado. Mudar aqui invalida o cache do cliente.
  'catalog_version': 'v1',

  // Gamificação (servidor é a verdade; estes valores são só para EXIBIR previsões)
  'hearts_max': 5,
  'hearts_regen_minutes': 30,
  'xp_lesson_base': 20,
  'streak_freeze_enabled': false,

  // MVP
  'duel_enabled': true,
  'friends_enabled': true,
  'offline_download_enabled': false, // ver docs/00-CORRECOES.md C7

  // Roadmap — arquitetado, desligado
  'realtime_duel_enabled': false,
  'leagues_enabled': false,
  'clans_enabled': false,
  'certificates_enabled': false,
  'labs_enabled': false,
  'subscription_enabled': false,
  'b2b_whitelabel_enabled': false,
  'friends_search_enabled': false,

  // Notificações
  'inactivity_hours': '24,72,168',
  'push_daily_cap': 3,
};
