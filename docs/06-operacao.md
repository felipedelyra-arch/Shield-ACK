# 6. Escala, custo, carga e cenários offline

## 6.1 SLOs

| Indicador | Alvo | Medição |
|---|---|---|
| p95 leitura de tela (cache quente) | < 50 ms | Performance Monitoring, trace custom |
| p95 `submitQuiz` | < 300 ms | log da Function + trace do cliente |
| p95 `startLesson` / `getLessonPlayback` | < 600 ms | idem |
| Taxa de erro 5xx nas Callables | < 0,5 % | Cloud Logging + alerta |
| Itens do outbox mortos (`dead`) | < 0,1 % | telemetria do cliente |
| Divergência de XP (ledger vs cache) | 0 | `reconcileXp` diária |

**Honestidade sobre o p95 de 300ms:** só é atingível em `submitQuiz` com
`minInstances: 1`. Sem ele, o cold start da 2ª geração adiciona 1,5–4s no p95
depois de ociosidade. Por isso `minInstances` fica **apenas nessa function** e
apenas em prod (`CRITICAL_PATH` em `functions/src/lib/init.ts`) — as demais ficam
em 0 e são compensadas por `concurrency: 80` + região única.

## 6.2 Custo estimado

Premissa: **10.000 MAU**, 3.000 DAU, 2 lições/dia por usuário ativo.
Preços São Paulo, Blaze, ordem de grandeza.

**Leituras/dia**

| Origem | Cálculo | Reads/dia |
|---|---|---|
| Catálogo | 3.000 × 1 (1º acesso do dia) | 3.000 |
| Progresso do módulo | 3.000 × 2 × ~8 | 48.000 |
| Questões do quiz | 3.000 × 2 × 10 | 60.000 |
| `submitQuiz` (servidor: lição, progresso, user, 10 gabaritos, 10 questões) | 3.000 × 2 × 23 | 138.000 |
| Perfil / amigos / ranking | 3.000 × ~25 | 75.000 |
| Agendadas (ranking 96×/dia, reconciliação) | — | ~60.000 |
| **Total** | | **≈ 384k/dia ≈ 11,5M/mês** |

| Item | Volume/mês | Custo aprox. |
|---|---|---|
| Firestore leituras | 11,5 M | US$ 4,00 |
| Firestore escritas | ~1,5 M | US$ 2,70 |
| Firestore armazenamento | 5 GB | US$ 0,90 |
| Cloud Functions (invocações + CPU) | ~2 M | US$ 8–15 |
| `minInstances: 1` em `submitQuiz` | 24/7 | **US$ 12–18** |
| RTDB (duelos) | ~3 GB | US$ 3,00 |
| FCM | ilimitado | US$ 0 |
| Cloudflare Stream (100 h de conteúdo, 40k h assistidas) | — | **US$ 200–400** |
| Egress / Storage (avatares) | — | US$ 2,00 |
| **Total Firebase** | | **≈ US$ 35–55/mês** |
| **Total com vídeo** | | **≈ US$ 240–460/mês** |

**A conclusão que importa: o vídeo é 85% do custo.** Toda otimização de Firestore
neste app rende centavos; a alavanca real é bitrate, encoding ladder e política de
cache na CDN. Por isso o vídeo fica **fora do Firebase** — pico de audiência não
toca o backend, e o custo é isolável e negociável.

**Onde o modelo quebra:** sem o documento agregado `catalog`, a coluna de leituras
sobe para ~1,1M/dia (+US$ 10/mês a 10k MAU, +US$ 100/mês a 100k). O ganho é
não-linear com o crescimento.

**Alertas:** budget no GCP em 50/80/100% do teto mensal, com notificação por e-mail
e Pub/Sub. `maxInstances: 20` global é o teto rígido que impede um loop de retry
de virar fatura.

## 6.3 Plano de teste de carga (k6)

Alvo: **500 usuários simultâneos**, 10 min, contra as Callables em **staging**
(nunca em prod — teste de carga em produção contamina métricas e ranking).

```js
// scripts/load/submit_quiz.js
import http from 'k6/http';
import { check, sleep } from 'k6';
import { uuidv4 } from 'https://jslib.k6.io/k6-utils/1.4.0/index.js';

export const options = {
  stages: [
    { duration: '2m', target: 100 },   // rampa
    { duration: '5m', target: 500 },   // patamar
    { duration: '1m', target: 1000 },  // pico: valida maxInstances e rate limit
    { duration: '2m', target: 0 },
  ],
  thresholds: {
    'http_req_duration{name:submitQuiz}': ['p(95)<300'],
    'http_req_failed': ['rate<0.005'],
    'checks': ['rate>0.99'],
  },
};

const URL = `https://${__ENV.REGION}-${__ENV.PROJECT}.cloudfunctions.net`;

export default function () {
  const idToken = __ENV.ID_TOKEN;          // token de conta de teste, gerado no setup
  const appCheck = __ENV.APP_CHECK_DEBUG;  // debug token registrado no console

  const res = http.post(
    `${URL}/submitQuiz`,
    JSON.stringify({ data: {
      lessonId: 'lessonLoadTest',
      idempotencyKey: uuidv4(),
      clientElapsedMs: 25000,
      answers: [{ questionId: 'qLoad1', value: 1 }],
    }}),
    {
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${idToken}`,
        'X-Firebase-AppCheck': appCheck,
      },
      tags: { name: 'submitQuiz' },
    },
  );

  check(res, {
    'status 200 ou 429 (rate limit funcionando)': (r) => r.status === 200 || r.status === 429,
  });
  sleep(3);
}
```

**O que cada cenário prova:**

| Cenário | Hipótese testada |
|---|---|
| Patamar de 500 VUs | p95 < 300ms com `minInstances: 1` |
| Pico de 1000 VUs | `maxInstances: 20` segura e devolve 429 em vez de escalar sem teto |
| Mesma `idempotencyKey` × 50 | XP creditado **uma vez**; 49 respostas com `replayed: true` |
| 1 uid × 100 req em 1 min | rate limit dispara em 30 e retorna `retryAfterSec` |
| Escrita direta no Firestore via SDK web | **negada** pelas Rules (é o teste que prova a regra de ouro) |
| Ranking com 50k `xpEvents` | `buildLeaderboard` termina dentro de 540s |

## 6.4 Cenários offline — testes obrigatórios

| Cenário | Comportamento esperado | Onde é testado |
|---|---|---|
| Modo avião durante o quiz | Submissão vai para o outbox; UI mostra `pending`; drena ao voltar | `test/outbox_offline_test.dart` |
| Rede instável (timeout a cada 2ª req) | Backoff exponencial **com jitter**; nunca duplica XP | idem |
| App encerrado no meio da submissão | Item fica `inflight`; no boot é reenviado; servidor devolve `outboxAck` com `replayed: true` | idem |
| Mesmo usuário em dois dispositivos | Progresso converge pelo **maior** (`lastPositionSec`, `bestScore`, lição concluída); XP reconciliado pelo ledger | idem |
| Backend fora do ar | Conteúdo em cache continua reproduzindo; progresso enfileira; `unavailable` é tratado como offline | idem |
| Payload inválido | Vai para `dead` **sem** retry — reenviar 8× um payload inválido só queima bateria | teste unitário do Outbox |

**Garantia oferecida pelo outbox: at-least-once.** Exactly-once no cliente é
impossível — o app pode morrer entre o commit do servidor e o ack. A exatidão vem
da idempotência do servidor, não da fila. Dizer o contrário seria mentir sobre a
garantia.

**Sincronização incremental:** por `updatedAt` + cursor. Nunca full sync.
Toda query tem `limit()`. Listener só na tela que precisa, com `autoDispose`.

## 6.5 Quando o modelo precisa mudar

| Gatilho | Migração |
|---|---|
| > 50k usuários no ranking | Agregação sai da Function e vai para o BigQuery; a Function só importa o resultado |
| > 100k MAU | Sharding de `counters` de 10 para 50; avaliar partição de `leaderboards` por liga |
| Duelo em tempo real ligado | Presença e cronômetro já estão no RTDB; falta apenas o listener no cliente |
| Catálogo > 1 MB | O doc agregado estoura o limite do Firestore. Migrar para um JSON no Storage com CDN + ETag |
