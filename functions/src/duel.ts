import { randomUUID } from 'node:crypto';
import { db, rtdb, FieldValue, Timestamp, SCHEMA_VERSION, txGetAll } from './lib/init';
import { guarded } from './lib/guard';
import { createDuelInput, respondDuelInput, submitDuelRoundInput } from './domain/schemas';
import { Err } from './lib/errors';
import { audit } from './lib/audit';
import { awardXp } from './lib/xp';
import { isCorrect, QuestionType } from './lib/grading';

/**
 * Máquina de estados do duelo. Transições legais, explícitas.
 * Qualquer transição fora desta tabela é rejeitada dentro da transação.
 *
 *   pending ──accept──> accepted ──first round──> in_progress ──last round──> finished
 *      │                    │                          │
 *      └──decline/expire────┴──────expire──────────────┴──> expired
 */
export type DuelState = 'pending' | 'accepted' | 'in_progress' | 'finished' | 'expired';

const LEGAL: Record<DuelState, DuelState[]> = {
  pending: ['accepted', 'expired'],
  accepted: ['in_progress', 'expired'],
  in_progress: ['finished', 'expired'],
  finished: [],
  expired: [],
};

export function canTransition(from: DuelState, to: DuelState): boolean {
  return LEGAL[from]?.includes(to) ?? false;
}

const ROUNDS = 5;
const ROUND_SECONDS = 30;
const INVITE_TTL_HOURS = 48;

export const createDuel = guarded(
  {
    action: 'createDuel',
    schema: createDuelInput,
    requireVerified: true, // superfície social
    limit: { max: 10, windowSec: 3600 },
  },
  async (data, ctx) => {
    if (data.opponentUid === ctx.uid) throw Err.invalidArg('SELF_DUEL');

    // Só duela com amigo. pairId determinístico evita duplicata de amizade.
    const pairId = [ctx.uid, data.opponentUid].sort().join('_');
    const friendship = await db.collection('friendships').doc(pairId).get();
    if (!friendship.exists) throw Err.locked('NOT_FRIENDS');

    // Idempotência: duelId derivado da chave do cliente. Retry devolve o mesmo duelo.
    const duelId = data.idempotencyKey.replace(/-/g, '');
    const ref = db.collection('duels').doc(duelId);

    const created = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (snap.exists) return false;

      tx.create(ref, {
        state: 'pending' satisfies DuelState,
        players: [ctx.uid, data.opponentUid],
        challenger: ctx.uid,
        trackId: data.trackId,
        scores: { [ctx.uid]: 0, [data.opponentUid]: 0 },
        currentRound: 0,
        totalRounds: ROUNDS,
        expiresAt: Timestamp.fromMillis(Date.now() + INVITE_TTL_HOURS * 3600 * 1000),
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        schemaVersion: SCHEMA_VERSION,
      });
      return true;
    });

    if (created) {
      // Espelho de membros no RTDB — as rules do RTDB leem daqui para autorizar
      // presença e `answered` sem precisar consultar o Firestore.
      await rtdb().ref(`duelMembers/${duelId}`).set({ [ctx.uid]: true, [data.opponentUid]: true });
    }

    return { duelId, state: 'pending', created };
  },
);

export const respondDuel = guarded(
  { action: 'respondDuel', schema: respondDuelInput, requireVerified: true, limit: { max: 30, windowSec: 3600 } },
  async (data, ctx) => {
    const ref = db.collection('duels').doc(data.duelId);

    return db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) throw Err.notFound();

      const state = snap.get('state') as DuelState;
      const players = snap.get('players') as string[];

      // Só o desafiado responde. O desafiante não aceita o próprio convite.
      if (!players.includes(ctx.uid) || snap.get('challenger') === ctx.uid) throw Err.locked('NOT_INVITED');

      const target: DuelState = data.accept ? 'accepted' : 'expired';
      if (!canTransition(state, target)) throw Err.conflict(`ILLEGAL_TRANSITION_${state}_${target}`);

      if ((snap.get('expiresAt') as Timestamp).toMillis() < Date.now()) {
        tx.update(ref, { state: 'expired', updatedAt: FieldValue.serverTimestamp() });
        throw Err.conflict('DUEL_EXPIRED');
      }

      tx.update(ref, { state: target, updatedAt: FieldValue.serverTimestamp() });
      return { duelId: data.duelId, state: target };
    });
  },
);

export const submitDuelRound = guarded(
  { action: 'submitDuelRound', schema: submitDuelRoundInput, requireVerified: true, limit: { max: 60, windowSec: 600 } },
  async (data, ctx) => {
    const duelRef = db.collection('duels').doc(data.duelId);
    const roundRef = duelRef.collection('rounds').doc(String(data.round));

    const outcome = await db.runTransaction(async (tx) => {
      const [duelSnap, roundSnap] = await txGetAll(tx, duelRef, roundRef);
      if (!duelSnap.exists || !roundSnap.exists) throw Err.notFound();

      const players = duelSnap.get('players') as string[];
      if (!players.includes(ctx.uid)) throw Err.locked('NOT_A_PLAYER');

      const state = duelSnap.get('state') as DuelState;
      if (state !== 'accepted' && state !== 'in_progress') throw Err.conflict(`ILLEGAL_STATE_${state}`);
      if (data.round !== (duelSnap.get('currentRound') as number)) throw Err.conflict('WRONG_ROUND');

      const answersByUid = (roundSnap.get('answers') as Record<string, unknown>) ?? {};
      // Replay de rodada: resposta já registrada é imutável.
      if (answersByUid[ctx.uid]) throw Err.conflict('ROUND_ALREADY_ANSWERED');

      const deadline = (roundSnap.get('deadlineAt') as Timestamp | undefined)?.toMillis() ?? Infinity;
      const late = Date.now() > deadline;

      const questionIds = roundSnap.get('questionIds') as string[];
      const given = new Map(data.answers.map((a) => [a.questionId, a.value]));

      // Correção server-side contra answerKeys. Mesmo caminho do quiz: o gabarito
      // nunca sai da function, e o placar é do servidor, não do cliente.
      const keySnaps = await tx.getAll(...questionIds.map((q) => db.collection('answerKeys').doc(q)));
      const qSnaps = await tx.getAll(
        ...questionIds.map((q) => db.collection('lessons').doc(roundSnap.get('lessonId')).collection('questions').doc(q)),
      );

      let correct = 0;
      if (!late) {
        questionIds.forEach((qid, i) => {
          const type = qSnaps[i]?.get('type') as QuestionType;
          if (keySnaps[i]?.exists && isCorrect(type, given.get(qid), keySnaps[i]!.get('correct'))) correct++;
        });
      }

      const speedBonus = late ? 0 : Math.max(0, Math.round((1 - data.clientElapsedMs / (ROUND_SECONDS * 1000)) * 2));
      const points = correct * 10 + speedBonus;

      tx.update(roundRef, {
        [`answers.${ctx.uid}`]: { correct, points, late, submittedAt: Timestamp.now() },
        updatedAt: FieldValue.serverTimestamp(),
      });

      const scores = { ...(duelSnap.get('scores') as Record<string, number>) };
      scores[ctx.uid] = (scores[ctx.uid] ?? 0) + points;

      const bothAnswered = Object.keys({ ...answersByUid, [ctx.uid]: true }).length === players.length;
      const isLastRound = data.round === (duelSnap.get('totalRounds') as number) - 1;

      let nextState: DuelState = state === 'accepted' ? 'in_progress' : state;
      if (bothAnswered && isLastRound) nextState = 'finished';

      if (nextState !== state && !canTransition(state, nextState)) {
        throw Err.conflict(`ILLEGAL_TRANSITION_${state}_${nextState}`);
      }

      tx.update(duelRef, {
        scores,
        state: nextState,
        currentRound: bothAnswered && !isLastRound ? data.round + 1 : data.round,
        finishedAt: nextState === 'finished' ? FieldValue.serverTimestamp() : null,
        updatedAt: FieldValue.serverTimestamp(),
      });

      return { points, correct, late, scores, state: nextState, players, bothAnswered, isLastRound };
    });

    // --- Fora da transação: XP do vencedor (idempotente pelo eventId) e RTDB.
    if (outcome.state === 'finished') {
      const [a, b] = outcome.players as [string, string];
      const winner =
        outcome.scores[a]! > outcome.scores[b]! ? a : outcome.scores[b]! > outcome.scores[a]! ? b : null;

      if (winner) {
        await awardXp({
          uid: winner,
          eventId: `duel-${data.duelId}`, // determinístico: um duelo paga XP uma vez, sempre
          amount: 50,
          reason: 'duel_win',
          ref: `duels/${data.duelId}`,
        });
      }
      await rtdb().ref(`duels/${data.duelId}`).remove();
      await audit('duel_finished', ctx.uid, 'info', { duelId: data.duelId, winner: winner ?? 'draw' });
    } else if (outcome.bothAnswered) {
      // Próxima rodada: só o estado efêmero vai para o RTDB (1 Hz de cronômetro
      // custaria ~300 reads de Firestore por duelo; aqui custa bytes).
      await rtdb().ref(`duels/${data.duelId}/state`).set({
        round: data.round + 1,
        deadlineAt: Date.now() + ROUND_SECONDS * 1000,
        phase: 'answering',
      });
      await rtdb().ref(`duels/${data.duelId}/answered`).remove();
    }

    return {
      points: outcome.points,
      correct: outcome.correct,
      late: outcome.late,
      scores: outcome.scores,
      state: outcome.state,
    };
  },
);

export const _internal = { canTransition, ROUNDS, ROUND_SECONDS, randomUUID };
