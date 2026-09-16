# 0. Prompt mestre — fonte de verdade do projeto

> Este é o briefing original do produto, salvo aqui porque é a especificação
> autoritativa. Os demais documentos de `docs/` derivam dele. Se houver
> divergência entre este arquivo e qualquer outro, **este arquivo vence**.

---

## 0. PAPEL

Atue como um time sênior composto por: Arquiteto de Software Mobile (Flutter),
Especialista em Cyber Security (AppSec + Mobile Security), Engenheiro de Backend
serverless no Firebase e Game Designer de aprendizagem. Justifique tecnicamente
cada decisão. Nunca entregue código "de exemplo didático" que não sirva em
produção.

**Premissa inegociável:** este é um app que ensina cibersegurança. Uma
vulnerabilidade nele destrói a credibilidade do produto. Segurança é requisito
transversal, não um módulo.

## 1. VISÃO DO PRODUTO

App mobile (Android + iOS) de ensino gamificado em Cibersegurança, Redes, DevOps
e DevSecOps.

Referências: Duolingo (trilha, streak, ligas, vidas, notificações de rivalidade)
e Alura (profundidade técnica, videoaulas, trilhas de carreira).

Núcleo: videoaulas em trilhas, cada aula seguida de questionário que libera o
próximo passo. Retenção via gamificação e duelos entre amigos.

## 2. ESCOPO

**MVP (v1):**

- Login com Google + cadastro por e-mail/senha
- Trilhas → módulos → lições (videoaula + quiz)
- Progresso persistente e desbloqueio sequencial
- XP, níveis, streak, vidas/energia
- Amigos + ranking
- Duelo 1x1 assíncrono
- Push de inatividade e de "seu amigo te ultrapassou"

**Roadmap** (arquitetar prevendo, sem implementar agora): duelo em tempo real,
ligas semanais, clãs/turmas, painel administrativo com upload de aulas,
certificados, laboratórios práticos, assinatura paga, modo B2B white label.

Deixe explícito quais interfaces, coleções e feature flags (Remote Config)
atendem ao roadmap.

## 3. STACK OBRIGATÓRIA

**Mobile:** Flutter (canal stable), Dart null-safe, Riverpod (ou Bloc —
justifique), go_router, freezed + json_serializable, dio (para APIs próprias),
drift/hive_ce ou isar para cache local criptografado, flutter_secure_storage,
local_auth, freeRASP, video_player/better_player com HLS.

**Firebase (via FlutterFire):**

- `firebase_auth` — Google Sign-In + e-mail/senha
- `cloud_firestore` — dados de domínio, com persistência offline habilitada
- `firebase_database` (Realtime Database) — apenas estado efêmero de duelo ativo
  e presença
- `cloud_functions` — toda lógica sensível (Callable + triggers + scheduled)
- `firebase_app_check` — Play Integrity (Android) + App Attest (iOS)
- `firebase_messaging` + `flutter_local_notifications` — push
- `firebase_remote_config` — feature flags e parâmetros de gamificação
- `firebase_crashlytics` + `firebase_performance` — observabilidade
- `cloud_storage` — apenas assets estáticos (thumbnails, avatares), não vídeo

**Vídeo:** serviço dedicado (Cloudflare Stream, Mux ou Bunny) com HLS adaptativo
e URLs assinadas de curta duração geradas por Cloud Function. Vídeo nunca em
bucket público.

**Regra de ouro:** o cliente nunca escreve direto em coleções de progresso, XP,
vidas, duelo ou ranking. Essas escritas passam obrigatoriamente por Callable
Functions. Security Rules negam escrita do cliente nelas.

## 4. ARQUITETURA

Clean Architecture + feature-first. Entregue a árvore completa:

```
lib/
  core/            # erros, result, di, theme, constants, extensions
  core/firebase/   # inicialização, App Check, wrappers de Firestore/Functions
  core/security/   # SecurityService, PinningService, IntegrityService, BiometricGate
  data/            # datasources (firebase/local), models, mappers, repositories impl
  domain/          # entities, repositories (abstrações), usecases
  presentation/    # features/<feature>/{pages,widgets,controllers,state}
features:
  auth, onboarding, tracks, lesson_player, quiz, progress,
  gamification (xp, streak, leagues), friends, duel, notifications, profile, settings
functions/         # Cloud Functions (TypeScript), estrutura modular por domínio
```

`domain` não importa Flutter nem SDK do Firebase. Dependências apontam para
dentro. Repositórios retornam `Result<Failure, T>` — exceção do Firebase jamais
chega à UI.

## 5. MODELO DE DADOS (Firestore)

Modele para leitura barata e escrita controlada, não em formato relacional.
Entregue o mapa de coleções, o custo de leitura estimado por tela e as Security
Rules completas.

```
users/{uid}                          # perfil público-limitado, xp, level, streak, hearts
users/{uid}/progress/{lessonId}      # status, lastPositionSec, completedAt, version
users/{uid}/xpEvents/{eventId}       # ledger append-only, ID = idempotency key
users/{uid}/private/{doc}            # e-mail, prefs, dados sensíveis — só o dono lê
tracks/{trackId}
tracks/{trackId}/modules/{moduleId}
tracks/{trackId}/modules/{moduleId}/lessons/{lessonId}
lessons/{lessonId}/questions/{qId}         # enunciado + opções SEM gabarito
answerKeys/{qId}                           # gabarito — Rules: allow read, write: if false
friendships/{pairId}                       # ID determinístico ordenado (uidA_uidB)
duels/{duelId} + duels/{duelId}/rounds/{n}
leaderboards/{periodId}/members/{uid}      # escrito só por Function agendada
devices/{tokenId}
auditLogs/{logId}                          # write-only via Functions
counters/{name}/shards/{shardId}           # contadores distribuídos
```

**Requisitos obrigatórios do modelo:**

- Gabarito nunca trafega para o cliente. `answerKeys` é inacessível por Rules; só
  o Admin SDK lê. A correção acontece em Callable Function.
- Limite de 1 escrita/segundo sustentada por documento: proibido contador global
  em documento único. Use sharded counters ou agregação agendada.
- XP é derivado do ledger, não um número editável. O campo `users/{uid}.xp` é
  cache escrito exclusivamente por Function.
- Desnormalize o necessário para que a tela de trilha custe 1 leitura de
  documento, não N.
- Todo documento com `createdAt`, `updatedAt` e `schemaVersion` para migração.
- Índices compostos declarados em `firestore.indexes.json`, versionados no
  repositório.
- Exportação agendada para BigQuery para métricas e relatórios — jamais rodar
  analytics em cima do Firestore de produção.

## 6. SECURITY RULES (tratar como código de produção)

- Default deny. Nenhuma coleção aberta.
- Leitura: usuário lê apenas o próprio `users/{uid}` e subcoleções; conteúdo
  (`tracks`, `lessons`) leitura autenticada; `answerKeys` e `auditLogs` fechados
  para sempre.
- Escrita do cliente permitida somente em: edição de perfil (campos
  whitelistados, com validação de tipo e tamanho) e preferências.
- Escrita em `progress`, `xpEvents`, `hearts`, `duels`, `leaderboards`,
  `friendships`: negada ao cliente, exclusiva do Admin SDK.
- `request.auth.token.email_verified` como pré-condição onde fizer sentido.
- App Check obrigatório (enforce) em Firestore, Storage, Functions e RTDB.
- Entregue suíte de testes automatizados das Rules com o Firebase Emulator
  (`@firebase/rules-unit-testing`), cobrindo caso permitido e caso negado de cada
  regra. **Rules sem teste é rule quebrada.**

## 7. AUTENTICAÇÃO

- Firebase Auth: Google (OAuth com PKCE) + e-mail/senha.
- Senha: política mínima, checagem contra listas de vazamento, proteção de
  enumeração de e-mail habilitada no console.
- Verificação de e-mail obrigatória antes de liberar recursos sociais (amigos,
  duelo, ranking).
- Hashing: gerenciado pelo Firebase (scrypt). Se houver qualquer credencial fora
  do Firebase Auth, usar Argon2id ou bcrypt cost ≥ 12 — nunca SHA/MD5.
- Custom claims para papéis (`student`, `teacher`, `admin`), setados só por
  Function administrativa; nunca pelo cliente.
- Rate limiting e lockout progressivo via Function + App Check + Identity
  Platform.
- Revogação de refresh token no logout e ao detectar comprometimento
  (`revokeRefreshTokens`); cliente trata `auth/id-token-revoked`.
- Gestão multi-dispositivo com listagem e revogação de sessão.
- Bloqueio de conta e trigger `beforeCreate`/`beforeSignIn` (Identity Platform)
  para validar domínio, App Check e política de risco.

## 8. TRILHA, VIDEOAULA E QUESTIONÁRIO

- Desbloqueio sequencial validado na Function, não no cliente. O app desenha a
  trilha; quem autoriza iniciar a lição é `startLesson()`.
- URL do vídeo entregue por `getLessonPlayback()` — assinada, curta, vinculada ao
  uid e revalidada.
- Player: retomar do segundo exato, velocidade, legendas, download offline
  criptografado, FLAG_SECURE no Android e overlay de proteção no iOS nas telas de
  conteúdo.
- Watch-time em heartbeat com envio em lote, tolerante a perda de rede (escrita
  agrupada para não estourar custo de writes).
- Quiz: múltipla escolha, V/F, associação, ordenação de comandos, preenchimento
  de terminal.
- Submissão via `submitQuiz(lessonId, answers, idempotencyKey)` → Function
  corrige contra `answerKeys`, grava tentativa, emite `xpEvent` com ID igual à
  idempotency key (retry nunca duplica XP), retorna acertos + explicações.

## 9. GAMIFICAÇÃO E DUELOS

- XP, nível, streak (com fuso do usuário) e vidas/energia calculados
  exclusivamente server-side. Regeneração de vidas por timestamp, nunca timer
  local.
- Anti-cheat obrigatório: cliente só exibe. Valide tempo mínimo plausível de
  resposta, frequência de submissões e padrões anômalos; registre em
  `auditLogs`.
- Duelo: máquina de estados explícita (`pending` → `accepted` → `in_progress` →
  `finished`/`expired`), transições em `runTransaction` do Firestore. Expiração
  por Cloud Scheduler.
- Estado efêmero do duelo ativo (rodada atual, presença, cronômetro) no Realtime
  Database — mais barato e com latência menor que listener de Firestore para
  atualização de alta frequência. O resultado final é persistido no Firestore
  pela Function.
- Ranking: Function agendada agrega e grava
  `leaderboards/{periodId}/members/{uid}` já ordenado e paginado. Proibido
  ordenar agregação ao vivo. Para ranking global grande, usar contadores
  shardeados + BigQuery.
- Amizade por código/username. E-mail de terceiro nunca exposto.

## 10. NOTIFICAÇÕES

- FCM (Android + APNs no iOS), com `devices/{tokenId}` por usuário e limpeza
  automática de token inválido no retorno de erro do envio.
- Gatilhos: inatividade (24h, 72h, 7d — parametrizável via Remote Config),
  streak em risco, amigo te ultrapassou, desafio recebido, duelo prestes a
  expirar.
- Agendamento por Cloud Scheduler + Function, respeitando fuso horário e janela
  de silêncio do usuário.
- Preferências granulares por tipo + opt-out total. Sem dado sensível no payload.
- Deduplicação (`collapse_key`) e teto diário por usuário — rivalidade saudável
  ≠ spam.
- Consultas de inatividade por índice em `lastActiveAt`, processadas em lote
  paginado (nunca varrer a coleção inteira).

## 11. OFFLINE-FIRST E CONTINUIDADE DE PROGRESSO

**Requisito de produto:** o usuário nunca perde a sequência em que parou.

- Persistência offline do Firestore habilitada — resolve leitura e cache
  automaticamente.
- Ela **não** resolve escrita de domínio, porque as escritas passam por Callable
  Functions, que não têm fila offline nativa. Portanto: implemente **outbox
  local** (banco criptografado) para ações de progresso → fila persistente →
  chamada da Function → confirmação → marcação como sincronizado.
- Retry com backoff exponencial + jitter; fila sobrevive a app morto
  (WorkManager/BGTaskScheduler).
- Toda Callable é idempotente por `idempotencyKey` gravada como ID de documento.
- Conflito determinístico e documentado: progresso monotônico (maior lição
  concluída vence), XP reconciliado pelo ledger.
- Sincronização incremental por `updatedAt`/cursor, nunca full sync.
- Testes de cenário: modo avião, rede instável, app encerrado no meio da
  submissão, mesmo usuário em dois dispositivos.

## 12. ESCALA, CUSTO E CONCORRÊNCIA

Firestore escala horizontalmente, mas quebra por design de dados e explode por
custo. Trate os dois.

- **Hotspotting:** IDs sequenciais concentram carga em um tablet. Use IDs
  aleatórios; nunca `lesson_0001`, `lesson_0002` como chave de escrita quente.
- 1 escrita/s sustentada por documento e 500 operações por batch/transação são
  limites rígidos — projete em torno deles.
- Leitura de catálogo (trilhas/lições) via documento agregado + cache local +
  Remote Config de versão, para que abrir o app custe poucas leituras.
- Cold start das Functions: `minInstances` nas Callables do caminho crítico
  (login, `startLesson`, `submitQuiz`); `maxInstances` em todas para evitar
  fatura descontrolada.
- Rate limiting por uid dentro da Function (contador com TTL) + App Check
  enforce.
- Paginação por cursor em toda lista. Nenhuma query sem `limit()`.
- Listeners em tempo real só nas telas que precisam, com `cancel()` no
  `dispose` — listener vazado é custo recorrente.
- Vídeo 100% na CDN, fora do Firebase, para que pico de audiência não afete o
  backend.
- Graceful degradation: com backend fora, o app segue reproduzindo conteúdo em
  cache e enfileira progresso.
- Defina SLOs e orçamento (ex.: p95 < 300ms nas leituras, N usuários
  simultâneos, teto de custo/mês) e entregue plano de teste de carga (k6 contra
  as Callables) + alertas de budget no GCP.

## 13. SEGURANÇA MOBILE (FLUTTER)

Atue como Especialista Sênior em Cyber Security e Arquitetura Mobile. Implemente
stack de segurança robusta prevenindo ataques, vulnerabilidades, vazamento de
dados e garantindo criptografia ponta a ponta (Data at Rest e Data in Transit).
Entregue guia técnico, arquitetura de arquivos e código Dart/Flutter:

### 13.1 Armazenamento seguro (Data at Rest)

- `SecurityService` com `flutter_secure_storage` guardando tokens, chave do banco
  local e material criptográfico no Keystore (Android) e Keychain (iOS), com
  `AndroidOptions(encryptedSharedPreferences: true)` e
  `accessibility: first_unlock_this_device` no iOS.
- Geração de chave AES-256 com gerador criptograficamente seguro, persistida no
  armazenamento seguro e usada para inicializar banco local criptografado
  (`hive_ce` com `HiveAesCipher`, ou `isar`/`drift` com SQLCipher).
- Cache offline do Firestore contém dados do usuário: trate o dispositivo como
  hostil e nunca guarde nele dado sensível que não precise estar lá.
- Rotina de **wipe total** (chaves, banco, cache do Firestore, vídeos offline,
  tokens FCM) em logout, falha de integridade ou detecção de root/jailbreak.

### 13.2 Comunicação segura (Data in Transit)

- Cliente `dio` com timeouts, retry idempotente e interceptors de
  auth/erro/refresh para APIs próprias (URLs de vídeo, webhooks, integrações).
- SSL Pinning por hash SHA-256 da chave pública (SPKI), com pin primário + pin
  de backup para sobreviver à rotação de certificado.
- **Limitação real a documentar:** os SDKs do Firebase usam a própria pilha de
  rede e não expõem pinning configurável. Pinar `*.googleapis.com` é inviável e
  quebraria o app na rotação de certificados do Google. Portanto: pinning
  aplica-se ao seu domínio (CDN de vídeo, APIs próprias) e a defesa contra MitM
  no tráfego Firebase vem de App Check + Certificate Transparency + ATS/Network
  Security Config. Explique isso no guia em vez de fingir que o pinning cobre
  tudo.
- `cleartextTrafficPermitted=false` no Android e ATS sem exceções no iOS.
- Expiração de sessão, refresh transparente do ID token, limpeza de token
  inválido e logout forçado em `id-token-revoked`.

### 13.3 Anti-tampering e integridade

- freeRASP (ou `flutter_jailbreak_detection`) detectando root, jailbreak,
  emulador não autorizado, hooking (Frida/Xposed), debugger anexado e app
  repackaged.
- Política **graduada**, não binária: telemetria → degradação de funcionalidade
  sensível → bloqueio. Justifique a política adotada.
- Reforço server-side por Firebase App Check em modo enforce (Play Integrity no
  Android, App Attest no iOS) — a checagem local sozinha é contornável; o App
  Check é o que efetivamente barra cliente não autêntico no backend.
- `local_auth` protegendo telas críticas, com fallback para PIN do app e
  tratamento de dispositivo sem biometria.

### 13.4 Proteção do código e build

- Comandos de build de produção com ofuscação:
  ```
  flutter build appbundle --release --obfuscate --split-debug-info=build/symbols/android
  flutter build ipa --release --obfuscate --split-debug-info=build/symbols/ios
  ```
  com versionamento dos símbolos e upload para o Crashlytics (senão os crashes
  ficam ilegíveis).
- `build.gradle`: `minifyEnabled true`, `shrinkResources true`, regras de keep
  para Flutter, Firebase e plugins.
- Nenhum segredo embarcado. `google-services.json` e `GoogleService-Info.plist`
  **não são segredos** — são identificadores públicos; a proteção real vem de
  Security Rules + App Check. Deixe isso explícito, é o mal-entendido mais comum
  em projeto Firebase.

## 14. SEGURANÇA DE BACKEND E DADOS

Bloco obrigatório, adaptado ao serverless:

- Validação e sanitização de toda entrada nas Cloud Functions (schema com `zod`
  ou equivalente). Nunca confiar no cliente.
- **Injeção:** não há SQL aqui, mas valem os equivalentes — nunca montar path de
  documento ou query com string crua vinda do cliente; whitelist de campos em
  toda escrita; proteção contra NoSQL injection e mass assignment. Onde houver
  SQL (BigQuery, banco externo), queries parametrizadas obrigatórias.
- **Menor privilégio:** Security Rules default-deny, service account com papel
  mínimo, Admin SDK exclusivamente nas Functions, custom claims só por Function
  administrativa.
- Dependências sempre atualizadas.
- Hash de senha com bcrypt ou Argon2 em qualquer credencial fora do Firebase
  Auth.
- HTTPS/TLS obrigatório em todo tráfego.
- AES-256 em repouso: gerenciado pelo Google no Firestore; criptografia
  adicional em campo para dados sensíveis e no banco local do app.
- **Arquitetura BFF:** Cloud Functions são o BFF. O app nunca fala direto com
  serviço de terceiro nem carrega chave de terceiro.
- Segredos exclusivamente em Secret Manager / `functions:secrets` — nunca no
  app, nunca no repositório, nunca em `functions.config()` versionado.
- Ofuscação/minificação do cliente.
- Varredura de vulnerabilidades: `npm audit` a cada nova lib nas Functions,
  `dart pub outdated` + `osv-scanner` no app, e `snyk test` ou Socket CLI
  periodicamente antes de cada deploy.

**Complementos específicos:**

- CORS restritivo e headers de segurança nas Functions HTTP.
- Logging estruturado sem PII + `auditLogs` para ações sensíveis.
- LGPD: base legal, política de privacidade, exportação e exclusão de conta
  (Function que apaga Auth + Firestore + Storage + FCM), retenção definida,
  consentimento para push e telemetria.
- Threat model resumido (STRIDE) das superfícies: auth, quiz, duelo, vídeo,
  notificações, Rules.

## 15. QUALIDADE E ENTREGA

- Clean code, SOLID, try-catch em toda fronteira de I/O, comentários apenas nos
  trechos críticos.
- Testes: unitário (domain/usecases), widget (telas principais), integração
  (login → aula → quiz → XP) com Firebase Emulator Suite, testes das Security
  Rules e testes de segurança (token expirado, root detectado, replay de
  submissão, escrita direta no Firestore tentando burlar a Function).
- CI/CD com lint, análise estática, testes no emulador, scan de dependências,
  deploy de Rules/Indexes/Functions versionado e build assinado.
- Ambientes separados (dev/staging/prod) em projetos Firebase distintos, com
  flavors no Flutter.
- Observabilidade: Crashlytics com símbolos, Performance Monitoring, Cloud
  Logging, alertas de erro e de custo.

## 16. FORMATO DA RESPOSTA

Entregue de forma modular e sequencial:

1. Decisões de arquitetura com trade-offs (incluindo o que Firestore não resolve
   bem neste app)
2. Árvore de diretórios (app + functions)
3. Mapa de coleções + `firestore.rules` + `firestore.indexes.json`
4. Contratos das Callable Functions (entrada, saída, erros, idempotência)
5. Código Dart por módulo, comentado
6. Código das Cloud Functions em TypeScript
7. Configurações de build e comandos
8. Checklist de segurança verificável, item a item, com como testar
9. Plano de teste de carga, custo estimado e cenários offline
10. Riscos residuais conhecidos

Antes de gerar, verifique a coerência técnica de cada etapa. Se alguma exigência
for inconsistente, inviável ou insegura na prática do Firebase, aponte o problema
e proponha a alternativa correta em vez de apenas obedecer.
