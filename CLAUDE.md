# Shield Ack

Especificação: `docs/00-PROMPT-MESTRE.md`. Estrutura: `docs/02-estrutura.md`. O que falta: `docs/08-checklist.md`.

## Como escrever código aqui

- Código para outra pessoa ler: nomes que dizem o que a coisa é, funções curtas, sem truque.
- Antes de criar, procure: helper, tipo ou padrão que já existe no projeto vem primeiro.
- Nada especulativo: sem interface com uma implementação, sem config para valor fixo, sem "para depois".
- Comentário explica o *porquê*, nunca o *o quê*. Código óbvio não leva comentário.
- Diff mínimo. Não reformate nem renomeie o que não faz parte da tarefa.
- Lógica não trivial deixa um teste que quebra se ela quebrar.
- Segurança nunca é simplificada: validação zod, `guarded()`, Rules, App Check, wipe.

## Camadas (Flutter)

- `domain/` não importa Flutter nem Firebase — `scripts/check_layering.sh` verifica.
- Callable só por `core/firebase/functions_client.dart`.
- DI via Riverpod (`core/di/providers.dart`), sem get_it.
- Repositório traduz exceção em `Failure`; UI não vê exceção crua.

## Antes de commitar

```sh
flutter analyze && dart format --set-exit-if-changed lib test
scripts/check_layering.sh
npm --prefix functions run lint && npm --prefix functions run build
npm --prefix functions test          # emulador
```

Commits e docs em português.
