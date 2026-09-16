# 0. Inconsistências do briefing — correções aplicadas

O prompt pedia explicitamente para apontar o que é inconsistente, inviável ou inseguro
na prática do Firebase. Segue o que foi corrigido, com a decisão adotada.

---

### C1. Caminho de `lessons` contraditório

O briefing define **duas** localizações para a mesma entidade:

```
tracks/{trackId}/modules/{moduleId}/lessons/{lessonId}   # aninhada
lessons/{lessonId}/questions/{qId}                       # raiz
```

São coleções diferentes. Uma lição aninhada 4 níveis abaixo não é endereçável por
`lessons/{id}`, e Security Rules para path aninhado profundo ficam ilegíveis.

**Decisão:** `lessons/{lessonId}` na raiz, com `trackId`/`moduleId`/`order` como campos.
`tracks/{t}/modules/{m}` guarda apenas `lessonIds: [..]` ordenado. Ganhos: rule única,
`collectionGroup` desnecessário, e o gabarito em `answerKeys/{qId}` fica a 1 nível.

---

### C2. "Tela de trilha custa 1 leitura" é impossível com o modelo proposto

Com `tracks → modules → lessons` em subcoleções, desenhar a trilha custa
`1 + N_modules + N_lessons` leituras. O requisito e o modelo se contradizem.

**Decisão:** documento agregado `catalog/{version}` contendo a árvore inteira
(trilhas → módulos → lições, sem gabarito, sem URL de vídeo). Publicado por Function
administrativa a cada mudança de conteúdo. Cliente lê **1 documento**, cacheia local,
e só revalida quando `remote_config.catalog_version` muda. `tracks/`, `modules/` e
`lessons/` continuam existindo como fonte de verdade para o admin e para as Functions.

Custo: 1 read na primeira abertura do dia, 0 depois. Sem isso, 60 lições = 60 reads/abertura.

---

### C3. `cloud_storage` não existe

O pacote FlutterFire é **`firebase_storage`**. Corrigido em `pubspec.yaml`.

---

### C4. Três bancos locais para o mesmo papel

O briefing lista `drift`/`hive_ce`/`isar` como alternativas, mas o outbox exige
**transação** (marcar item como enviado + gravar resposta atomicamente) e
**query por status + ordenação**. Hive é key-value, não serve bem para fila transacional.

**Decisão:** `drift` + `sqlcipher_flutter_libs`, chave AES-256 vinda do
`flutter_secure_storage`. Um banco só. `hive_ce`/`isar` descartados.

---

### C5. Certificate Transparency não é enforçado no Android

O briefing afirma que a defesa contra MitM no tráfego Firebase vem de
"App Check + Certificate Transparency + ATS/Network Security Config".

Isso é verdade no iOS (`NSRequiresCertificateTransparency` no ATS) e **falso no Android**:
o Network Security Config **não tem** flag de CT. O Chrome faz CT; apps Android nativos não.

**Decisão:** no Android a defesa real contra MitM no tráfego Firebase é
(a) TrustManager padrão + `cleartextTrafficPermitted=false`,
(b) **não confiar em CAs instaladas pelo usuário** — `<trust-anchors>` apenas `system`,
que é o que efetivamente barra Burp/mitmproxy num device sem root,
(c) App Check enforce, que invalida o tráfego mesmo se interceptado.
Documentado em `docs/05-seguranca-mobile.md`.

---

### C6. "URL de vídeo assinada vinculada ao uid" — só parcialmente possível

Tokens de Cloudflare Stream / Mux assinam **expiração, ID do vídeo, restrição de país/IP
e regras de download**. Não existe binding criptográfico a um `uid` do Firebase — o
provedor de vídeo não conhece seu Auth.

**Decisão:** o `uid` vai no *claim customizado* do token (Cloudflare Stream suporta
`accessRules` + campos arbitrários assinados) e é usado para **auditoria e correlação de
abuso**, não como controle de acesso. O controle de acesso real é:
TTL curto (120s para o manifesto), 1 token por `(uid, lessonId)` com rate limit na Function,
e `auditLogs` correlacionando emissões. Compartilhar link continua possível dentro da janela
de 120s — isso é um **risco residual aceito**, listado em `docs/07-riscos.md`.
Proteção forte contra redistribuição = DRM (Widevine L1 / FairPlay), fora do MVP.

---

### C7. Download offline "criptografado" de HLS não é o que parece

`better_player` faz cache de HLS, mas não entrega um container criptografado com sua chave.
Criptografar o segmento você mesmo exige um proxy local (servidor HTTP em `127.0.0.1`
decriptando on-the-fly) — que é exatamente onde o conteúdo volta a ficar em claro.

**Decisão MVP:** download offline **desligado por feature flag**. Quando ligar:
HLS com AES-128 key rotation, chave entregue por Function com TTL, e a chave (não o vídeo)
guardada no Keystore. Assumido e documentado que isso é *deterrence*, não DRM.

---

### C8. `email_verified` como pré-condição quebra o Google Sign-In... e não quebra

Contas Google já chegam com `email_verified: true`. A regra vale de fato só para
e-mail/senha. Sem isso, o usuário de e-mail/senha fica preso sem entender por quê.

**Decisão:** `email_verified` é exigido apenas nas superfícies sociais
(amigos, duelo, ranking, envio de código de amizade), nunca em trilha/aula/quiz.
Aprender nunca é bloqueado por verificação de e-mail.

---

### C9. `minInstances` + "teto de custo" se contradizem

`minInstances: 1` em 3 Callables na 2ª geração custa ~US$ 25–40/mês **ociosos**, 24/7,
antes de qualquer usuário. O briefing pede isso e um teto de custo agressivo.

**Decisão:** `minInstances` **só em `submitQuiz`** (caminho crítico, sensível a p95) e
apenas em produção, controlado por variável de ambiente. `startLesson` e
`getLessonPlayback` ficam em 0 e são compensados por `concurrency: 80` (Fluid/2ª geração)
+ região única `southamerica-east1` (latência Brasil). Números em `docs/06-operacao.md`.

---

### C10 (bônus). PIN próprio do app é um downgrade de segurança

Implementar fallback de PIN em Dart significa você guardando e comparando um segredo
de 4–6 dígitos — pior que o Keystore. O `local_auth` já cai para credencial do dispositivo.

**Decisão:** `biometricOnly: false`. Sem PIN caseiro.
