# 4. Contratos das Callable Functions

Regras válidas para **todas**:

- Passam por `guarded()`: App Check → Auth → claims → zod → rate limit → handler.
- Erro chega ao cliente como `FirebaseFunctionsException`; `message` carrega o código
  do contrato. Tradução para `Failure` em `lib/core/firebase/functions_client.dart`.
- Região: `southamerica-east1`. Chamar outra região é 404.
- Códigos comuns: `AUTH_REQUIRED`, `APP_CHECK_REQUIRED`, `EMAIL_NOT_VERIFIED`,
  `RATE_LIMITED` (+`details.retryAfterSec`), `INVALID_<CAMPO>`, `NOT_FOUND`, `INTERNAL`.

| Function | Verif.? | Rate limit | Idempotente |
|---|---|---|---|
| `bootstrapProfile` | não | 10 / 1h | sim (natural) |
| `startLesson` | não | 60 / 5min | sim (natural) |
| `getLessonPlayback` | não | 20 / 10min | não (emite token novo) |
| `submitQuiz` | não | 30 / 5min | **sim (`idempotencyKey`)** |
| `syncWatchProgress` | não | 60 / 10min | parcial (monotônico) |
| `createDuel` | **sim** | 10 / 1h | **sim (`idempotencyKey`)** |
| `respondDuel` | **sim** | 30 / 1h | sim (transição ilegal → `aborted`) |
| `submitDuelRound` | **sim** | 60 / 10min | sim (rodada imutável) |
| `sendFriendRequest` | **sim** | 20 / 1h | não |
| `respondFriendRequest` | **sim** | 50 / 1h | sim |
| `updateUsername` | não | 3 / 24h | sim |
| `registerDevice` | não | 20 / 1h | sim |
| `requestAccountDeletion` | não | 3 / 24h | sim |
| `exportMyData` | não | 3 / 24h | sim |
| `publishCatalog` | role `admin` | 10 / 1h | não |
| `setUserRole` | role `admin` | 20 / 1h | sim |

---

## `submitQuiz` — o contrato mais importante

```ts
// entrada
{
  lessonId: string,          // [A-Za-z0-9_-]{1,64}
  idempotencyKey: string,    // UUID v4 — vira o ID de users/{uid}/xpEvents/{id}
  clientElapsedMs: number,   // 0..3_600_000 — SINAL de anti-cheat, não nota
  answers: [{ questionId: string, value: number|boolean|number[]|string }]  // 1..20
}

// saída
{
  passed: boolean, score: number,            // 0..1
  correctCount: number, total: number,
  xpAwarded: number, totalXp: number, level: number,
  hearts: number, streakDays: number,
  perQuestion: [{ questionId, correct, explanation }],  // sem a resposta das erradas
  replayed: boolean                          // true = veio do ack, nada foi reprocessado
}
```

**Erros:** `LESSON_LOCKED` (permission-denied) · `NO_HEARTS` (permission-denied) ·
`DUPLICATE_QUESTION` (invalid-argument) · `NOT_FOUND` · `RATE_LIMITED`.

**Idempotência — o mecanismo exato:**
`users/{uid}/xpEvents/{idempotencyKey}` é criado com `tx.create()`. A segunda chamada
com a mesma chave falha dentro da transação e a função devolve `duplicate: true`.
Não é `if (exists)` seguido de `set` — esse padrão tem janela de corrida entre o
`get` e o `set`. O ID do documento **é** a trava.

Além disso, `users/{uid}/outboxAck/{idempotencyKey}` guarda o resultado por 7 dias:
um retry devolve o objeto original com `replayed: true` sem recorrigir nada.

**Por que `clientElapsedMs` não define a nota:** é um número que o cliente escolhe.
Ele só alimenta `auditLogs` e um piso grosseiro (1,2s por questão). A nota vem
exclusivamente da comparação contra `answerKeys` no servidor.

---

## `getLessonPlayback`

```ts
{ lessonId: string }  →  { hlsUrl: string, expiresAt: number, resumeAtSec: number }
```

TTL de 120s. Exige `startLesson` prévio bem-sucedido — pedir a URL direto retorna
`LESSON_LOCKED` e gera `playback_without_start` em `auditLogs`.
Limitação assumida sobre binding ao `uid`: `docs/00-CORRECOES.md` C6.

---

## `submitDuelRound`

```ts
{ duelId, round: 0..9, idempotencyKey, clientElapsedMs, answers: [...] }
  → { points, correct, late, scores: {uid:number}, state }
```

Transições válidas apenas conforme a tabela em `functions/src/duel.ts`.
`ILLEGAL_TRANSITION_<de>_<para>` e `ROUND_ALREADY_ANSWERED` retornam `aborted`.
O placar é calculado no servidor; o cliente só exibe.

---

## Roadmap — interfaces já previstas, desligadas por flag

| Feature | Flag (Remote Config) | O que já existe |
|---|---|---|
| Duelo em tempo real | `realtime_duel_enabled` | `/duels/{id}/state` no RTDB, rules e presença |
| Ligas semanais | `leagues_enabled` | `periodId` ISO week, `leaderboards/{periodId}` |
| Clãs / turmas | `clans_enabled` | claim `role: teacher`, `pairId` determinístico |
| Painel administrativo | — | `publishCatalog`, `setUserRole`, claim `admin` |
| Certificados | `certificates_enabled` | ledger `xpEvents` prova a conclusão |
| Laboratórios | `labs_enabled` | tipo de questão `fill` (terminal) já modelado |
| Assinatura | `subscription_enabled` | claim `role`, gate no `guarded()` |
| B2B white label | `b2b_whitelabel_enabled` | flavors no Flutter, `tenantId` reservado no schema |
