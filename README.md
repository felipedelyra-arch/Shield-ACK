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
npm --prefix functions run test:local          # lógica pura (15 testes)
cd test/rules && npm ci && npm test            # Security Rules (33 casos)
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

## Armadilhas de ambiente encontradas (reais, nesta máquina)

1. **Caminho com espaço/acento quebra o analysis server.** Em
   `~/Área de trabalho/Aplicativo Shield Ack`, o `flutter analyze` morre com
   `FormatException: Unexpected end of input` — o framing LSP calcula
   Content-Length em caracteres, não em bytes. Workaround: analisar por um
   symlink ASCII (`ln -s "$PWD" /tmp/shieldack && cd /tmp/shieldack`).
   O CI não sofre disso; máquinas de dev com pasta em português, sim.

2. **`freezed` 2.x + `analyzer` 7.x crasha todo codegen.** Sintoma:
   `Missing implementation of visitDotShorthandPropertyAccess` e o aviso
   `SDK language version 3.13.0 is newer than analyzer language version 3.9.0`.
   Resolvido com `flutter pub upgrade --major-versions`. Se voltar, é esse.

3. **`sqlcipher_flutter_libs` acima de 0.6 é um shim vazio.** No `sqlite3` 3.x o
   SQLCipher é selecionado por `hooks.user_defines.sqlite3.source: sqlcipher` no
   `pubspec.yaml`. Sem essa chave o `PRAGMA key` é ignorado **em silêncio** e o
   banco nasce em claro — por isso `app_database.dart` valida
   `PRAGMA cipher_version` e lança.

## Ver a interface no celular (modo demo)

O app ainda não tem `firebase_options.dart` real, então existe um modo que roda
**só a interface**, com dados em memória:

```bash
flutter run --dart-define=SHIELDACK_ENV=demo
```

Esse modo desliga App Check, Crashlytics, banco local e outbox — ou seja, toda a
camada de segurança. Um `assert` em `main.dart` impede que ele coexista com
`SHIELDACK_ENV=prod`, e o gabarito do questionário fica em `lib/demo/`
justamente para deixar claro que aquilo **nunca** vive no cliente em produção.

### Conectar o aparelho por USB

1. No Android: Ajustes → Sobre o telefone → tocar 7× em "Número da versão".
2. Ajustes → Opções do desenvolvedor → ligar **Depuração USB**.
3. Conectar o cabo e aceitar o diálogo "Permitir depuração USB" que aparece na tela.
4. Conferir: `flutter devices` (ou `adb devices` — deve listar `device`, não `unauthorized`).

Se o aparelho não aparecer, quase sempre é uma destas três: cabo só de carga,
o diálogo de autorização não foi aceito, ou o modo USB está em "Somente carga" —
troque para "Transferência de arquivos (MTP)".

### Plugin ponytail

Fixado no projeto em `.claude/settings.json` (marketplace
`DietrichGebert/ponytail`), então quem clonar recebe junto.
