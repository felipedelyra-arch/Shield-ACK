# 1. Decisões de arquitetura e trade-offs

## 1.1 Riverpod vs Bloc — decisão: **Riverpod 2 (code-gen)**

| Critério | Riverpod | Bloc |
|---|---|---|
| Boilerplate por tela | ~1 notifier | 1 bloc + events + states |
| Cache/invalidação de leitura | nativo (`ref.watch`, `keepAlive`, `family`) | manual |
| Cancelamento de listener no dispose | automático (`autoDispose` + `ref.onDispose`) | manual |
| Composição de dependências | é o DI | precisa `get_it`/`provider` junto |
| Rastreabilidade de transição de estado | pior | melhor (stream de eventos) |

**Justificativa:** o custo dominante deste app é **listener do Firestore vazado**
(cobra por documento entregue, para sempre). `autoDispose` do Riverpod fecha o stream
no dispose da rota por padrão — Bloc exige disciplina manual e vaza em navegação
`push`/`pop` rápida. Trocamos auditabilidade de eventos (que recuperamos com
`ProviderObserver` → Crashlytics) por corte estrutural de custo.

**Exceção:** a máquina de estados do duelo usa `StateNotifier` com transições
explícitas e enum selado, porque ali a auditabilidade do evento importa mais.

## 1.2 O que o Firestore **não** resolve bem neste app

Isto é o núcleo do desenho. Cada item abaixo gerou uma decisão estrutural.

**a) Agregação.** Firestore não tem `ORDER BY SUM()`. Ranking ao vivo é impossível.
→ Function agendada materializa `leaderboards/{periodId}/members/{uid}` já ordenado.

**b) 1 escrita/segundo sustentada por documento.** Contador global de "usuários ativos"
ou "total de XP da plataforma" em um doc = hotspot garantido.
→ `counters/{name}/shards/{0..N}` + rollup agendado. `N=10` no MVP, parametrizável.

**c) Alta frequência.** Cronômetro de duelo a 1 Hz num listener de Firestore custa
1 read por tick por espectador. 2 jogadores × 5 rodadas × 30s = ~300 reads por duelo.
→ Estado efêmero no **Realtime Database** (cobra por GB trafegado, não por operação).
Resultado final vai para o Firestore, uma escrita.

**d) Escrita atrás de Callable não tem fila offline.** `cloud_firestore` enfileira writes
offline; `cloud_functions` **não**. Como toda escrita de domínio é Callable (regra de ouro),
perdemos a fila nativa.
→ **Outbox local transacional** em SQLCipher. Detalhado em §1.3.

**e) Custo de leitura de catálogo.** Ver `docs/00-CORRECOES.md` C2.

**f) Busca textual.** Procurar amigo por nome não existe no Firestore
(`>=`/`<=` em prefixo é o máximo, sem acentuação nem fuzzy).
→ MVP: amizade por **código de 8 chars** (`usernames/{lower}` para unicidade), zero busca.
Roadmap: Typesense/Algolia via extensão, atrás de flag `friends_search_enabled`.

## 1.3 Outbox local vs "coleção de comandos" no Firestore

Havia duas formas de resolver (d):

**Opção A — coleção de comandos.** Cliente escreve em `commands/{uid}/queue/{idemKey}`,
Rules permitem apenas `create` com schema estrito, trigger `onCreate` processa.
*Prós:* fila offline grátis (Firestore já enfileira), retry nativo, sobrevive a app morto
sem WorkManager. *Contras:* abre superfície de escrita do cliente; rate limit só
aproximado (Rules não contam); custo de 1 write + 1 trigger-read + 1 delete por ação;
e um cliente comprometido pode inundar a coleção offline e despejar tudo de uma vez.

**Opção B — outbox local (adotada).** Fila em SQLCipher, worker chama a Callable.
*Prós:* zero superfície de escrita; rate limit real dentro da Function; controle total de
backoff e de lote. *Contras:* código nosso; precisa WorkManager/BGTaskScheduler para
sobreviver a app encerrado; precisa teste de cenário sério.

**Decisão: B.** A premissa do produto é "uma vulnerabilidade destrói a credibilidade".
Não abrimos superfície de escrita para economizar ~200 linhas de fila. O custo é
explicitamente pago em `lib/data/datasources/local/outbox.dart` + testes de cenário.

## 1.4 Fronteiras

- `domain/` não importa `package:flutter`, `firebase_*` nem `dio`. Verificado no CI
  por `scripts/check_layering.sh` (grep que falha o build).
- Repositórios retornam `Result<Failure, T>`. `FirebaseException` é traduzida no
  datasource; nunca sobe.
- `presentation/` não importa `data/`. Só `domain/`.
- Cloud Functions são o **BFF**. O app nunca tem chave de terceiro
  (Cloudflare Stream, provedor de e-mail) no binário.

## 1.5 Fronteira de confiança (resumo STRIDE)

| Superfície | Ameaça principal | Controle |
|---|---|---|
| Auth | Enumeração de e-mail, credential stuffing | Proteção de enumeração no console, lockout progressivo por Function, App Check |
| Quiz | Leitura do gabarito, replay de submissão, bot | `answerKeys` fechado por Rules, idempotência por ID de documento, tempo mínimo plausível, rate limit |
| Duelo | Manipulação de resultado, race em aceite | Transição só em `runTransaction`, servidor é a fonte do placar |
| Vídeo | Redistribuição de link | Token 120s, rate limit por uid, auditoria. Risco residual assumido (C6) |
| Push | Vazamento de PII no payload, spam | Payload sem PII, teto diário, `collapse_key` |
| Rules | Escrita direta burlando Function | Default deny + suíte de teste no emulador |
| Cliente | Root/hook/repack | freeRASP graduado + App Check enforce (o que realmente barra) |
