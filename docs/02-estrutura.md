# 2. Árvore de diretórios

```
shieldack/
├── lib/
│   ├── main.dart                      # bootstrap: Firebase → Keystore → banco → integridade → outbox
│   ├── app.dart
│   ├── firebase_options.dart          # gerado por flutterfire configure (NÃO é segredo)
│   ├── core/
│   │   ├── error/{failure.dart, result.dart}
│   │   ├── di/providers.dart          # Riverpod = DI; sem get_it
│   │   ├── firebase/
│   │   │   ├── firebase_bootstrap.dart  # App Check ANTES de tudo, persistência, RC, Crashlytics
│   │   │   └── functions_client.dart    # único ponto de chamada de Callable
│   │   ├── security/
│   │   │   ├── security_service.dart    # Keystore/Keychain, chave AES-256
│   │   │   ├── integrity_service.dart   # freeRASP, política graduada
│   │   │   ├── pinning_service.dart     # SPKI pinning (domínios próprios)
│   │   │   ├── biometric_gate.dart      # local_auth, fallback do SO
│   │   │   ├── secure_screen.dart       # FLAG_SECURE / overlay iOS
│   │   │   └── session_guard.dart       # revogação + wipe total
│   │   ├── network/dio_client.dart
│   │   └── {theme, constants, extensions}.dart
│   ├── data/
│   │   ├── datasources/
│   │   │   ├── firebase/{auth, catalog, progress, duel}_remote_ds.dart
│   │   │   └── local/{app_database.dart, outbox.dart, outbox_worker.dart}
│   │   ├── models/                    # DTOs freezed + json_serializable
│   │   ├── mappers/                   # DTO ↔ entidade
│   │   └── repositories/              # implementações, traduzem exceção → Failure
│   ├── domain/
│   │   ├── entities/                  # sem Flutter, sem Firebase (CI verifica)
│   │   ├── repositories/              # interfaces
│   │   └── usecases/
│   └── presentation/
│       ├── router.dart                # go_router + redirect de auth/integridade
│       └── features/
│           ├── auth/            onboarding/      tracks/
│           ├── lesson_player/   quiz/            progress/
│           ├── gamification/    friends/         duel/
│           └── notifications/   profile/         settings/
│               └── {pages,widgets,controllers,state}/
│
├── functions/                          # TypeScript, modular por domínio
│   ├── src/
│   │   ├── index.ts                    # superfície pública
│   │   ├── lib/
│   │   │   ├── init.ts                 # admin, região, maxInstances, getAll tipado
│   │   │   ├── guard.ts                # wrapper de TODA Callable
│   │   │   ├── errors.ts  rateLimit.ts  audit.ts
│   │   │   ├── xp.ts  hearts.ts  streak.ts  grading.ts   # lógica pura, testada
│   │   ├── domain/schemas.ts           # zod, whitelist de charset em IDs
│   │   ├── startLesson.ts  getLessonPlayback.ts  submitQuiz.ts
│   │   ├── syncWatchProgress.ts  duel.ts  friends.ts  devices.ts  lgpd.ts
│   │   ├── admin/publishCatalog.ts
│   │   ├── triggers/onUserCreate.ts    # blocking functions + bootstrapProfile
│   │   └── scheduled/index.ts          # ranking, expiração, reconciliação, push
│   └── test/logic.test.ts              # 15 testes de lógica pura
│
├── test/rules/                         # suíte das Security Rules no emulador
│   ├── setup.ts
│   └── firestore.rules.test.ts         # 33 casos: permitido E negado
│
├── firestore.rules      firestore.indexes.json
├── database.rules.json  storage.rules   firebase.json
├── android/app/{build.gradle.kts, proguard-rules.pro}
├── android/app/src/main/res/xml/{network_security_config.xml, data_extraction_rules.xml}
├── ios/Runner/Info-security.plist
├── scripts/check_layering.sh
├── .github/workflows/ci.yml
└── docs/00..08
```

**Regras de fronteira, verificadas no CI por `scripts/check_layering.sh`:**
`domain/` não importa Flutter nem SDK; `presentation/` não importa `data/`.
