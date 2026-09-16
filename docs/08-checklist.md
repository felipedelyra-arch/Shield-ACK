# 8. Checklist de segurança verificável

Item a item, com **como testar**. Um item sem teste é um item não implementado.

## Security Rules

- [ ] Default deny ativo · `npm --prefix test/rules test` → bloco "default deny"
- [ ] `answerKeys` ilegível por qualquer cliente, inclusive admin · bloco "GABARITO"
- [ ] Questão publicada não contém campo de resposta · `publishCatalog` bloqueia + teste de rules
- [ ] Cliente não escreve em `progress` / `xpEvents` / `hearts` / `streak` · bloco "PROGRESSO E XP"
- [ ] Whitelist de campos no perfil (anti mass-assignment) · bloco "PERFIL"
- [ ] `updatedAt` forjado pelo cliente é negado · bloco "PERFIL"
- [ ] `/private` ilegível por terceiros · bloco "DADOS PRIVADOS"
- [ ] Social exige `email_verified` · bloco "SOCIAL"
- [ ] `auditLogs`, `rateLimits`, `counters` fechados · bloco "SERVER-ONLY"
- [ ] Anônimo não lê nada · bloco "NÃO AUTENTICADO"

**Teste manual decisivo:** com o SDK web e um token de usuário real, tentar
`setDoc(doc(db,'users/<uid>'), {xp: 999999})`. Deve falhar. É o teste que prova a
regra de ouro.

## App Check

- [ ] Enforce ligado em Firestore, Storage, Functions e RTDB (console)
- [ ] `curl` direto na Callable **sem** header `X-Firebase-AppCheck` → `failed-precondition`
- [ ] Debug token registrado apenas nos projetos dev/staging, nunca em prod
- [ ] `AndroidProvider.playIntegrity` / `AppleProvider.appAttest` em prod (`firebase_bootstrap.dart`)

## Autenticação

- [ ] Proteção de enumeração de e-mail ativa (Auth > Settings)
- [ ] Política de senha + checagem contra vazamento ativa (Identity Platform)
- [ ] `beforeCreate` nega provedor não previsto · teste no emulador
- [ ] `beforeSignIn` nega conta marcada `blocked: true`
- [ ] Custom claims setadas **só** por `setUserRole` (role admin) · tentar pelo cliente → negado
- [ ] `revokeRefreshTokens` derruba a sessão em < 1h · teste: revogar e chamar Callable
- [ ] Cliente trata `id-token-revoked` com wipe + logout · `SessionGuard`

## Cloud Functions

- [ ] Toda Callable exportada passa por `guarded()` · `grep -c 'export const' src/*.ts` vs `grep -c 'guarded('`
- [ ] Entrada validada por zod, sem exceção
- [ ] Nenhum path de documento montado com string crua do cliente · charset whitelist em `docId`
- [ ] `maxInstances` definido globalmente · `src/lib/init.ts`
- [ ] Rate limit por uid em toda Callable com efeito colateral
- [ ] Segredos só em Secret Manager · `grep -rn "functions.config()\|apiKey\s*=" functions/src` → vazio
- [ ] `npm audit --audit-level=high` sem findings

## Idempotência e anti-cheat

- [ ] `submitQuiz` × 50 com a mesma chave credita XP **uma vez** · teste no emulador
- [ ] Transição ilegal de duelo é rejeitada · `test/logic.test.ts`
- [ ] Resposta abaixo do piso de tempo é auditada e reprova
- [ ] Vidas regeneram por timestamp; mudar o relógio do device não cria vidas · `test/logic.test.ts`
- [ ] Streak usa o dia civil no fuso do usuário · `test/logic.test.ts`

## Cliente

- [ ] Banco local abre com SQLCipher · `PRAGMA cipher_version` não vazio (lança se vazio)
- [ ] Chave AES gerada com `Random.secure()`
- [ ] `sqlite3 shieldack.sqlite ".tables"` em device rooteado → **erro de arquivo cifrado**
- [ ] Wipe apaga Keystore + banco + cache do Firestore + token FCM
- [ ] Pinning com 2 pins, rejeita cert fora dos pins · proxy MitM com CA do sistema → conexão recusada
- [ ] `cleartextTrafficPermitted=false` · `adb shell` + tentativa HTTP → bloqueada
- [ ] Trust anchors só `system` em release · CA do Burp instalada → tráfego recusado
- [ ] ATS sem `NSAllowsArbitraryLoads`
- [ ] `allowBackup=false` · `adb backup` → vazio
- [ ] FLAG_SECURE na tela de aula · screenshot → tela preta
- [ ] Ofuscação ativa · `strings libapp.so | grep -i submitQuiz` → sem match legível
- [ ] Símbolos enviados ao Crashlytics · crash de teste aparece com stack legível
- [ ] freeRASP dispara nos 4 níveis · device rooteado, Frida anexado, APK repackaged

## LGPD

- [ ] Política de privacidade publicada, com base legal por finalidade
- [ ] Consentimento explícito para push e telemetria
- [ ] `exportMyData` devolve dados do titular
- [ ] `requestAccountDeletion` apaga Auth + Firestore + Storage + FCM · verificar no console
- [ ] Nenhum PII em `auditLogs` · `grep -n "email\|displayName" functions/src/lib/audit.ts` → vazio
- [ ] Payload de push sem dado sensível
- [ ] TTL configurado em `rateLimits` e `outboxAck`
- [ ] Retenção definida para `auditLogs` no BigQuery

## CI/CD

- [ ] `flutter analyze` + `dart format --set-exit-if-changed` sem erro
- [ ] `check_layering.sh` passa (domain não importa Flutter/Firebase)
- [ ] Testes de Rules rodam no emulador a cada PR
- [ ] `osv-scanner` no app + `npm audit` nas Functions a cada PR
- [ ] Deploy de Rules/Indexes/Functions versionado, nunca pelo console
- [ ] Projetos Firebase separados: dev / staging / prod
