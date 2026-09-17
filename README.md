# Shield Ack

Ensino gamificado em Cibersegurança, Redes, DevOps e DevSecOps.
Flutter + Firebase, com segurança como requisito transversal.

## Documentação

| # | Documento | Conteúdo |
|---|---|---|
| 00 | [Correções do briefing](docs/00-CORRECOES.md) | **Leia primeiro.** 10 inconsistências técnicas encontradas e as decisões tomadas |
| 01 | [Arquitetura](docs/01-arquitetura.md) | Riverpod vs Bloc, o que o Firestore não resolve, outbox vs fila de comandos, STRIDE |
| 02 | [Estrutura](docs/02-estrutura.md) | Árvore completa (app + functions) |
| 03 | [Modelo de dados](docs/03-dados.md) | Coleções, custo de leitura por tela, invariantes, hotspotting |
| 04 | [Contratos](docs/04-contratos.md) | Callables: entrada, saída, erros, idempotência, flags do roadmap |
| 05 | [Segurança mobile](docs/05-seguranca-mobile.md) | At rest, in transit, anti-tampering, build |
| 06 | [Operação](docs/06-operacao.md) | SLOs, custo estimado, k6, cenários offline |
| 07 | [Riscos residuais](docs/07-riscos.md) | 12 riscos aceitos, com gatilho de reavaliação |
| 08 | [Checklist](docs/08-checklist.md) | Item a item, com como testar |

## A regra de ouro

O cliente **nunca** escreve direto em progresso, XP, vidas, duelo, ranking ou
amizade. Essas escritas passam por Callable Function; as Security Rules negam
escrita do cliente nelas — e há um teste automatizado provando cada negação.

## Setup

```bash
# Flutter
flutter pub get
dart run build_runner build --delete-conflicting-outputs

# Functions
npm --prefix functions ci
npm --prefix functions run build

# Emulador completo
firebase emulators:start

# Testes
npm --prefix functions run test:local          # lógica pura
npm --prefix functions test                    # lógica + integração no emulador
cd test/rules && npm ci && npm test            # Security Rules
flutter test
./scripts/check_layering.sh                    # fronteiras de camada
```

## Build de produção

```bash
flutter build appbundle --release --flavor prod \
  --dart-define=SHIELDACK_ENV=prod \
  --dart-define=ANDROID_SIGNING_HASH="$ANDROID_SIGNING_HASH" \
  --obfuscate --split-debug-info=build/symbols/android

firebase crashlytics:symbols:upload --app="$FIREBASE_ANDROID_APP_ID" build/symbols/android
```

Sem o upload dos símbolos, os crashes ficam ilegíveis. O passo não é opcional.

## Ambientes

Projetos Firebase **separados** para dev / staging / prod, com flavors no Flutter.
Teste de carga roda só em staging.

## Ver só a interface (modo demo)

Roda **só a interface**, com dados em memória e sem Firebase:

```bash
flutter run --dart-define=SHIELDACK_ENV=demo
```

Esse modo desliga App Check, Crashlytics, banco local e outbox — ou seja, toda a
camada de segurança. Um `assert` em `main.dart` impede que ele coexista com
`SHIELDACK_ENV=prod`, e o gabarito do questionário fica em `lib/demo/`
justamente para deixar claro que aquilo **nunca** vive no cliente em produção.

## Rodar o app real contra o emulador do Firebase

Enquanto as Functions não estão publicadas (exigem plano Blaze), o app **de verdade**
(login, Rules, Callables, outbox, banco cifrado) roda contra o Firebase Emulator Suite,
com o mesmo ID do projeto dev e dados só na máquina. Só App Check e Crashlytics
ficam de fora, porque dependem da nuvem.

```bash
# 1. Emulador (Java 21) — deixe este terminal aberto
export JAVA_HOME=~/Android/jdk21 PATH=~/Android/jdk21/bin:$PATH
npm --prefix functions run build
firebase emulators:start --project dev --only auth,firestore,functions,database

# 2. Em outro terminal: trilhas, aulas e questões de exemplo em catalog/v1
npm --prefix functions run seed

# 3. Celular no cabo: as portas do PC aparecem como 127.0.0.1 no aparelho
for p in 9099 8080 5001 9000; do adb reverse tcp:$p tcp:$p; done
flutter run --flavor dev --dart-define=EMULATOR_HOST=127.0.0.1
```

A UI do emulador em http://127.0.0.1:4000 mostra os
usuários, o progresso e o XP gravados pelas Functions.

`EMULATOR_HOST` só funciona em build de debug: o HTTP em claro para 127.0.0.1 está
liberado apenas em `android/app/src/debug/`, e o app recusa subir com
`EMULATOR_HOST` em `SHIELDACK_ENV=prod`.

### Conectar o aparelho por USB

1. No Android: Ajustes → Sobre o telefone → tocar 7× em "Número da versão".
2. Ajustes → Opções do desenvolvedor → ligar **Depuração USB**.
3. Conectar o cabo e aceitar o diálogo "Permitir depuração USB" que aparece na tela.
4. Conferir: `flutter devices` (ou `adb devices` — deve listar `device`, não `unauthorized`).

Se o aparelho não aparecer, quase sempre é uma destas três: cabo só de carga,
o diálogo de autorização não foi aceito, ou o modo USB está em "Somente carga" —
troque para "Transferência de arquivos (MTP)".
