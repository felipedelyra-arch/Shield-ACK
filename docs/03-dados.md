# 3. Modelo de dados

Todo documento carrega `createdAt`, `updatedAt`, `schemaVersion` (int).
IDs de documentos de escrita quente são **aleatórios** (nunca `lesson_0001`) — ver §3.4.

## 3.1 Mapa de coleções

```
users/{uid}
  username, displayName, photoUrl, level, xp, streakDays, hearts,
  heartsUpdatedAt, lastActiveAt, tz, emailVerified, friendCode,
  createdAt, updatedAt, schemaVersion
  # xp/level/hearts/streakDays são CACHE. Fonte de verdade = xpEvents. Só Function escreve.
  # Cliente escreve APENAS: displayName, photoUrl, username (whitelist nas Rules).

users/{uid}/private/profile        # email, notifPrefs, quietHours, consentFlags, locale
users/{uid}/progress/{lessonId}    # status, lastPositionSec, watchedSec, completedAt, bestScore, version
users/{uid}/xpEvents/{eventId}     # LEDGER append-only. eventId == idempotencyKey. amount, reason, ref
users/{uid}/attempts/{attemptId}   # lessonId, score, answers, elapsedMs, createdAt
users/{uid}/outboxAck/{idemKey}    # (opcional) confirmação idempotente lida pelo cliente

catalog/{version}                  # DOC AGREGADO. Árvore completa. Sem gabarito, sem URL.
tracks/{trackId}                   # fonte de verdade (admin)
tracks/{trackId}/modules/{moduleId}  # lessonIds: [..] ordenado
lessons/{lessonId}                 # trackId, moduleId, order, videoAssetId, durationSec, xpReward
lessons/{lessonId}/questions/{qId} # type, prompt, options[]  -- SEM campo de resposta
answerKeys/{qId}                   # lessonId, correct, explanation   -- Rules: read/write: false

usernames/{usernameLower}          # { uid } — unicidade. Só Function escreve.
friendRequests/{reqId}             # from, to, status, createdAt
friendships/{pairId}               # pairId = "uidMenor_uidMaior". members[], createdAt
duels/{duelId}                     # state, players[], scores{}, currentRound, expiresAt
duels/{duelId}/rounds/{n}          # lessonId, questionIds[], answers{uid:..}, resolvedAt
leaderboards/{periodId}/members/{uid}   # rank, xp, displayName, photoUrl. Só Function agendada.
devices/{tokenId}                  # uid, platform, tz, appVersion, lastSeenAt
auditLogs/{logId}                  # actor, action, severity, meta. Write-only via Admin SDK.
counters/{name}/shards/{shardId}   # value:int
rateLimits/{uid}__{action}         # count, windowStart, expireAt (TTL policy)
deletionRequests/{uid}             # LGPD: status, requestedAt, completedAt
```

### Realtime Database (estado efêmero apenas)

```
/duels/{duelId}/state     { round, deadlineAt, phase }
/duels/{duelId}/answered  { uid: true }
/presence/{uid}           { online, lastSeen }   # onDisconnect()
```

Nada aqui é fonte de verdade. Perder o RTDB inteiro degrada UX de duelo, não perde dado.

## 3.2 Custo de leitura por tela

| Tela | Leituras (frio) | Leituras (quente) | Como |
|---|---|---|---|
| Splash / boot | 1 | 0 | `catalog/{v}` cacheado; versão vem do Remote Config |
| Home / trilhas | 0 | 0 | do `catalog` já em cache |
| Detalhe do módulo | 0 + P | 0 | P = progresso das lições daquele módulo, 1 query com `limit` |
| Player de aula | 1 | 0 | `users/{uid}/progress/{lessonId}` |
| Quiz | Q | Q | Q = nº de questões (`lessons/{id}/questions`, `limit(20)`) |
| Perfil | 1 | 0 | `users/{uid}` |
| Amigos | ≤50 | ≤50 | `friendships` where `members array-contains uid`, paginado |
| Ranking | 1 página (20) | 20 | `leaderboards/{p}/members` orderBy rank, cursor |
| Duelo ativo | 2 + RTDB | 2 | doc do duelo + rodada; tick no RTDB |

**Sessão típica (1 aula + 1 quiz):** ~1 + 1 + 10 = **12 reads**. Sem o doc agregado seriam
~70. Detalhe do cálculo de custo em `docs/06-operacao.md`.

## 3.3 Invariantes obrigatórias

1. **Gabarito nunca trafega.** `answerKeys` é `read: false, write: false`. Só Admin SDK.
   Teste automatizado em `test/rules/answer_keys_test.ts` prova a negação.
2. **XP é derivado.** `users/{uid}.xp` é cache. A verdade é `sum(xpEvents.amount)`.
   Reconciliação agendada compara os dois e registra divergência em `auditLogs`.
3. **Idempotência por ID.** `xpEvents/{eventId}` usa `eventId = idempotencyKey`.
   Retry grava o mesmo ID → `create` falha → XP não duplica. Não é `if exists`, é o ID.
4. **Progresso é monotônico.** Conflito entre dispositivos resolve por
   `max(order da lição concluída)` e `max(bestScore)`. Documentado e testado.
5. **Sem contador em documento único.** Qualquer `+1` global vai para shards.

## 3.4 Hotspotting

Firestore particiona por range de chave. `lesson_0001..lesson_9999` coloca escritas
adjacentes no mesmo tablet. Regra aplicada:

- IDs de **conteúdo** (`lessons`, `tracks`): slug legível é aceitável — escrita rara (admin).
- IDs de **escrita quente** (`xpEvents`, `attempts`, `auditLogs`, `duels`): `crypto.randomUUID()`.
  Exceção: `xpEvents` usa a `idempotencyKey`, que **deve** ser UUIDv4 gerada no cliente —
  validada por regex na Function, justamente para não virar sequência.
- `leaderboards/{periodId}/members/{uid}`: `uid` já é aleatório. `periodId` = `2026-W38`
  concentra por semana, mas a escrita é de uma Function em lote controlado, não concorrente.

## 3.5 BigQuery

**Correção:** "exportação agendada" e o extension são coisas diferentes.
- `firestore-bigquery-export` (extension) faz **streaming** de mudanças por coleção —
  usado em `xpEvents`, `attempts`, `auditLogs`. Custo por evento.
- Export gerenciado (`gcloud firestore export`) roda em bucket e é **backup**, não analytics.

Usamos o extension nas 3 coleções acima + export diário para GCS como backup.
Nenhuma query de analytics toca o Firestore de produção.
