import { describe, it, expect, beforeAll } from 'vitest';
import { initializeApp, getApps, deleteApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import { randomUUID } from 'node:crypto';

/**
 * Idempotência do submitQuiz CONTRA O EMULADOR (docs/08-checklist.md,
 * "Idempotência e anti-cheat").
 *
 * O teste de lógica pura não serve aqui: a invariante que interessa é que
 * `awardXp` cria `xpEvents/{idempotencyKey}` dentro de uma transação, e o que
 * prova isso é o Firestore de verdade abortando a segunda escrita — não um
 * mock. Por isso este arquivo fala HTTP com a Callable real, com ID token
 * real, em vez de invocar o handler.
 */

const PROJECT = process.env.GCLOUD_PROJECT ?? 'demo-shieldack';
const REGION = 'southamerica-east1';
const FN_HOST = process.env.FUNCTIONS_EMULATOR_HOST ?? '127.0.0.1:5001';
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? '127.0.0.1:9099';

const callableUrl = (name: string) => `http://${FN_HOST}/${PROJECT}/${REGION}/${name}`;

if (getApps().length === 0) initializeApp({ projectId: PROJECT });
const db = getFirestore();
const auth = getAuth();

/**
 * Custom token -> ID token pelo REST do emulador de Auth. É o caminho que um
 * cliente real percorre; assinar um JWT na mão pularia a verificação que
 * queremos exercitar.
 */
async function idTokenFor(uid: string): Promise<string> {
  const customToken = await auth.createCustomToken(uid);
  const res = await fetch(
    `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=fake-api-key`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: customToken, returnSecureToken: true }),
    },
  );
  if (!res.ok) throw new Error(`signInWithCustomToken falhou: ${res.status} ${await res.text()}`);
  return (await res.json() as { idToken: string }).idToken;
}

interface CallResult {
  status: number;
  body: { result?: Record<string, unknown>; error?: { status?: string; message?: string } };
}

async function callSubmitQuiz(idToken: string, data: unknown): Promise<CallResult> {
  const res = await fetch(callableUrl('submitQuiz'), {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${idToken}`,
    },
    body: JSON.stringify({ data }),
  });
  return { status: res.status, body: await res.json() as CallResult['body'] };
}

const LESSON = 'lesson-idem-test';
const XP_REWARD = 20;
/** Acerto total => bônus de 1.25 aplicado pelo submitQuiz. */
const EXPECTED_XP = Math.round(XP_REWARD * 1.25);

/** Semeia o estado mínimo para a lição ser respondível: lição, questões, gabarito, progresso. */
async function seedUser(uid: string) {
  await db.collection('lessons').doc(LESSON).set({
    trackId: 'track-test',
    moduleId: 'module-test',
    order: 1,
    xpReward: XP_REWARD,
    schemaVersion: 1,
  });

  for (const [qid, correct] of [['q1', 0], ['q2', true]] as const) {
    await db.collection('lessons').doc(LESSON).collection('questions').doc(qid).set({
      type: typeof correct === 'boolean' ? 'boolean' : 'single',
      prompt: 'pergunta de teste',
      schemaVersion: 1,
    });
    await db.collection('answerKeys').doc(qid).set({
      lessonId: LESSON,
      correct,
      explanation: 'porque sim',
      schemaVersion: 1,
    });
  }

  await db.collection('users').doc(uid).set({
    xp: 0,
    level: 1,
    hearts: 5,
    heartsUpdatedAt: Timestamp.now(),
    streakDays: 0,
    lastStudyDay: null,
    tz: 'America/Sao_Paulo',
    schemaVersion: 1,
  });

  await db.collection('users').doc(uid).collection('progress').doc(LESSON).set({
    status: 'in_progress',
    bestScore: 0,
    attempts: 0,
    schemaVersion: 1,
  });
}

const answers = [
  { questionId: 'q1', value: 0 },
  { questionId: 'q2', value: true },
];
/** Acima do piso anti-cheat (1200ms por questão), senão `passed` vira false. */
const clientElapsedMs = answers.length * 1200 + 5_000;

describe('submitQuiz — idempotência contra o emulador', () => {
  beforeAll(() => {
    if (!process.env.FIRESTORE_EMULATOR_HOST) {
      throw new Error('Rode via `npm test` (firebase emulators:exec), não com vitest direto.');
    }
  });

  it('N chamadas concorrentes com a MESMA chave creditam XP uma única vez', async () => {
    // uid próprio por teste: o rate limit é por uid e vazaria entre os casos.
    const uid = 'uidIdempotenciaConcorrente01';
    await seedUser(uid);
    const token = await idTokenFor(uid);
    const idempotencyKey = randomUUID();

    // 25 e não 50: o rate limit do submitQuiz é 30/300s e o guard o aplica ANTES
    // do short-circuit de replay, então 50 baterias no limitador mediriam o
    // limitador, não a idempotência. O caso de estouro está no teste seguinte.
    const N = 25;
    const payload = { lessonId: LESSON, idempotencyKey, clientElapsedMs, answers };
    const results = await Promise.all(Array.from({ length: N }, () => callSubmitQuiz(token, payload)));

    // Sob disputa, perder a transação é aceitável se vier como CONTENTION (retentável,
    // fica no outbox) — nunca INTERNAL. O retry do outbox tem de convergir para 200.
    for (const [i, r] of results.entries()) {
      if (r.status === 200) continue;
      expect(r.body.error?.message, JSON.stringify(r.body)).toBe('CONTENTION');
      results[i] = await callSubmitQuiz(token, payload);
      expect(results[i]!.status, JSON.stringify(results[i]!.body)).toBe(200);
    }

    // A prova: um único evento no ledger, com o ID igual à chave.
    const events = await db.collection('users').doc(uid).collection('xpEvents').get();
    expect(events.size).toBe(1);
    expect(events.docs[0]!.id).toBe(idempotencyKey);
    expect(events.docs[0]!.get('amount')).toBe(EXPECTED_XP);

    // E o cache derivado bate com o ledger.
    const user = await db.collection('users').doc(uid).get();
    expect(user.get('xp')).toBe(EXPECTED_XP);

    // Os outros efeitos também são únicos: a chave trava a tentativa, não só o XP.
    const attempts = await db.collection('users').doc(uid).collection('attempts').get();
    expect(attempts.size).toBe(1);
    const progress = await db.collection('users').doc(uid).collection('progress').doc(LESSON).get();
    expect(progress.get('attempts')).toBe(1);

    // Exatamente uma resposta fez o trabalho; as demais são replay.
    const awarded = results.filter((r) => r.body.result?.xpAwarded === EXPECTED_XP);
    expect(awarded.length).toBeGreaterThanOrEqual(1);
    for (const r of results) {
      expect(r.body.result?.totalXp).toBe(EXPECTED_XP);
    }
  }, 60_000);

  it('replay sequencial devolve o resultado gravado, marcado como replayed', async () => {
    const uid = 'uidIdempotenciaSequencial1';
    await seedUser(uid);
    const token = await idTokenFor(uid);
    const idempotencyKey = randomUUID();
    const payload = { lessonId: LESSON, idempotencyKey, clientElapsedMs, answers };

    const first = await callSubmitQuiz(token, payload);
    expect(first.status, JSON.stringify(first.body)).toBe(200);
    expect(first.body.result?.replayed).toBe(false);
    expect(first.body.result?.xpAwarded).toBe(EXPECTED_XP);

    const second = await callSubmitQuiz(token, payload);
    expect(second.status).toBe(200);
    expect(second.body.result?.replayed).toBe(true);
    expect(second.body.result?.xpAwarded).toBe(EXPECTED_XP); // o resultado GRAVADO, não um novo crédito
    expect(second.body.result?.totalXp).toBe(EXPECTED_XP);

    const events = await db.collection('users').doc(uid).collection('xpEvents').get();
    expect(events.size).toBe(1);
  }, 60_000);

  it('chave DIFERENTE na mesma lição credita de novo — a trava é a chave, não a lição', async () => {
    const uid = 'uidIdempotenciaChaveNova1';
    await seedUser(uid);
    const token = await idTokenFor(uid);

    const a = await callSubmitQuiz(token, {
      lessonId: LESSON, idempotencyKey: randomUUID(), clientElapsedMs, answers,
    });
    const b = await callSubmitQuiz(token, {
      lessonId: LESSON, idempotencyKey: randomUUID(), clientElapsedMs, answers,
    });

    expect(a.status).toBe(200);
    expect(b.status).toBe(200);

    const events = await db.collection('users').doc(uid).collection('xpEvents').get();
    expect(events.size).toBe(2);

    const user = await db.collection('users').doc(uid).get();
    expect(user.get('xp')).toBe(EXPECTED_XP * 2);
  }, 60_000);

  it('resposta abaixo do piso de tempo reprova, não credita XP e é auditada', async () => {
    const uid = 'uidPisoDeTempoAntiCheat01';
    await seedUser(uid);
    const token = await idTokenFor(uid);

    const r = await callSubmitQuiz(token, {
      lessonId: LESSON, idempotencyKey: randomUUID(), clientElapsedMs: 100, answers, // tudo certo, rápido demais
    });

    expect(r.status, JSON.stringify(r.body)).toBe(200);
    expect(r.body.result?.passed).toBe(false);
    expect(r.body.result?.xpAwarded).toBe(0);

    const logs = await db.collection('auditLogs')
      .where('actorUid', '==', uid).where('action', '==', 'quiz_too_fast').get();
    expect(logs.size).toBe(1);
  }, 30_000);

  it('responder só parte das questões é recusado — senão a nota seria sobre as que se sabe', async () => {
    const uid = 'uidRespostaIncompleta0001';
    await seedUser(uid);
    const token = await idTokenFor(uid);

    const r = await callSubmitQuiz(token, {
      lessonId: LESSON, idempotencyKey: randomUUID(), clientElapsedMs, answers: [answers[0]],
    });

    expect(r.status).toBe(400);
    expect(r.body.error?.message).toBe('INCOMPLETE_ANSWERS');
    const events = await db.collection('users').doc(uid).collection('xpEvents').get();
    expect(events.size).toBe(0);
  }, 30_000);

  it('sem Authorization a Callable recusa antes de tocar o banco', async () => {
    const res = await fetch(callableUrl('submitQuiz'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        data: { lessonId: LESSON, idempotencyKey: randomUUID(), clientElapsedMs, answers },
      }),
    });
    expect(res.status).toBe(401);
  }, 30_000);
});
