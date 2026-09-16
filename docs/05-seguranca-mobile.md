# 5. Segurança mobile (Flutter)

## 5.0 O mal-entendido mais comum em projeto Firebase

**`google-services.json` e `GoogleService-Info.plist` NÃO são segredos.**

São identificadores públicos: API key do Firebase, app ID, project ID, sender ID.
Qualquer pessoa extrai isso de um APK em 30 segundos com `unzip` + `strings`.
Google documenta isso explicitamente. Ofuscar, criptografar ou tirar do repositório
esses arquivos **não adiciona segurança nenhuma** — só dificulta o build.

A proteção real, em ordem de eficácia:

1. **Security Rules** — decidem quem lê e escreve o quê. Sem elas, a API key
   pública é acesso total.
2. **App Check (enforce)** — Play Integrity / App Attest atestam **no servidor do
   Google** que a requisição veio do seu binário legítimo. Um `curl` com a API key
   extraída do APK é rejeitado. Este é o controle que mais importa.
3. **Callable Functions** — lógica sensível fora do alcance do cliente.

O que **é** segredo e nunca entra no app: chave de assinatura do Cloudflare Stream,
service account do Admin SDK, chave de provedor de e-mail. Tudo em **Secret Manager**,
acessado só por Cloud Function. Ver `functions/src/getLessonPlayback.ts`.

---

## 5.1 Data at Rest

| Dado | Onde | Proteção |
|---|---|---|
| Chave AES-256 do banco | Keystore / Keychain | `flutter_secure_storage`, `encryptedSharedPreferences`, `first_unlock_this_device`, `synchronizable: false` |
| Outbox + cache de catálogo | SQLite | SQLCipher com a chave acima |
| Cache do Firestore | disco do app | Não criptografado pelo SDK. Mitigação: `cacheSizeBytes` limitado, `allowBackup=false`, e nada sensível fora de `/private` |
| Token do Firebase Auth | gerenciado pelo SDK | Não duplicamos. Duas cópias = uma fora do ciclo de revogação |
| Vídeo offline | — | **Desligado no MVP** (`docs/00-CORRECOES.md` C7) |

**Geração da chave:** `Random.secure()` — CSPRNG do SO. `Random()` aqui seria
vulnerabilidade real: PRNG previsível derruba a criptografia inteira.

**`PRAGMA key` precisa ser o PRIMEIRO comando da conexão.** Depois de qualquer
outra instrução, o SQLCipher já decidiu o modo e ignora a chave **em silêncio**,
deixando o banco em claro. `app_database.dart` valida com `PRAGMA cipher_version`
e lança se o SQLCipher não estiver ativo — falhar alto é melhor que gravar em claro.

**Wipe total** (`SessionGuard.forceLogout`), em logout / token revogado / ataque ativo:
FCM → `Firestore.terminate()` → `clearPersistence()` → banco local → Keystore → `signOut()`.
Um lugar só, de propósito: limpeza espalhada é como se esquece uma superfície.

---

## 5.2 Data in Transit

**SSL pinning por SPKI, não por certificado.** Pinar o certificado quebra a cada
renovação (90 dias no Let's Encrypt). O SPKI sobrevive à renovação e só quebra numa
troca real de chave — exatamente o evento que queremos detectar.
**Dois pins obrigatórios** (primário + backup gerado e guardado offline); com um só,
perder a chave é app morto até nova release na loja.

### O escopo do pinning — limitação real, declarada

Os SDKs do Firebase usam a própria pilha de rede (gRPC/Cronet) e **não expõem
TrustManager configurável**. Pinar `*.googleapis.com` é inviável e, se fosse possível,
derrubaria o app na primeira rotação de certificado do Google.

**Portanto: o pinning cobre apenas domínios próprios** (CDN de vídeo, APIs do produto,
tudo que passa pelo `dio`). Para o tráfego Firebase a defesa é outra:

| Controle | Android | iOS |
|---|---|---|
| `cleartextTrafficPermitted=false` / ATS sem exceção | ✅ | ✅ |
| Trust anchors **apenas do sistema** (recusa CA instalada pelo usuário) | ✅ **é o que barra Burp/mitmproxy** | ✅ (comportamento padrão) |
| Certificate Transparency | ❌ **não existe no Network Security Config** | ✅ `NSRequiresCertificateTransparency` |
| App Check enforce (invalida o tráfego mesmo se interceptado) | ✅ | ✅ |

A linha marcada ❌ é a correção C5: afirmar que "CT protege o tráfego Firebase no
Android" é falso. O Chrome faz CT; apps Android nativos não.

**Sessão:** `idTokenChanges` + `getIdToken(true)` valida contra o servidor — sem
`force: true`, um token revogado continua aceito localmente por até 1h.
`user-token-expired` / `user-disabled` → `forceLogout`.

---

## 5.3 Anti-tampering — política graduada

| Nível | Sinal | Ação |
|---|---|---|
| `clean` | — | nada |
| `observed` | debugger, emulador, sem passcode | telemetria (Crashlytics custom key) |
| `compromisedDevice` | root/jailbreak, loja não oficial | desliga download offline e duelo ranqueado; **conteúdo continua acessível** |
| `activeAttack` | hooking (Frida/Xposed), app repackaged | wipe local + logout + revogação de sessão |

**Por que não bloquear no primeiro sinal de root:**

1. Detecção local é contornável **por definição** — o atacante controla o processo
   que executa a checagem. Bloquear não impede o atacante; só pune o usuário.
2. Uma parcela real do público de um app de **segurança** tem device rooteado de
   propósito. Expulsá-los destrói o produto para quem ele foi feito.
3. O que efetivamente barra cliente não autêntico é o **App Check** no backend,
   fora do alcance do atacante.

Hooking e repackaging recebem tratamento diferente porque **não acontecem por acidente**.

**Biometria:** `local_auth` com `biometricOnly: false` — fallback é a credencial do
**dispositivo**, não um PIN do app. PIN caseiro = nós guardando um segredo de 4–6
dígitos, pior que o Keystore (C10). Device sem credencial nenhuma não é bloqueado:
tornaria a conta inacessível.

**Telas de conteúdo:** `FLAG_SECURE` no Android (remover no `dispose` — deixá-lo
ligado quebra o preview no multitarefa); no iOS, detecção de `isCaptureActive` com
overlay, porque screenshot estático não é bloqueável. Nada disso impede uma câmera
apontada para a tela — o objetivo é elevar o custo da cópia casual.

---

## 5.4 Build de produção

```bash
# Android
flutter build appbundle --release --flavor prod \
  --dart-define=SHIELDACK_ENV=prod \
  --dart-define=ANDROID_SIGNING_HASH="$ANDROID_SIGNING_HASH" \
  --obfuscate --split-debug-info=build/symbols/android

# iOS
flutter build ipa --release --flavor prod \
  --dart-define=SHIELDACK_ENV=prod \
  --dart-define=IOS_TEAM_ID="$IOS_TEAM_ID" \
  --obfuscate --split-debug-info=build/symbols/ios
```

**`--split-debug-info` sem upload dos símbolos = crashes ilegíveis.** O passo abaixo
não é opcional; é o que separa "temos Crashlytics" de "conseguimos depurar":

```bash
firebase crashlytics:symbols:upload \
  --app="$FIREBASE_ANDROID_APP_ID" build/symbols/android
```

Os símbolos são versionados por `versionCode` e arquivados junto com o artefato do
build. Perder os símbolos de uma versão em produção é irreversível.

`minifyEnabled` + `shrinkResources` no `build.gradle.kts`, com regras de keep para
Flutter, Firebase, SQLCipher, biometria e **freeRASP** (ofuscar as classes de
detecção derrota a própria detecção).

`-assumenosideeffects` remove `Log.d/v/i` no release: uma linha de log com token é
um vazamento.
