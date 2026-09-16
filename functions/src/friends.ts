import { randomUUID } from 'node:crypto';
import { db, FieldValue, SCHEMA_VERSION, txGetAll } from './lib/init';
import { guarded } from './lib/guard';
import { sendFriendRequestInput, respondFriendRequestInput, updateUsernameInput } from './domain/schemas';
import { Err } from './lib/errors';
import { audit } from './lib/audit';

/**
 * Amizade por código, nunca por e-mail.
 *
 * Decisão de privacidade: aceitar e-mail aqui criaria um oráculo de enumeração —
 * "este e-mail tem conta?" — que é exatamente o que a proteção de enumeração do
 * Firebase Auth existe para evitar. O código de 8 chars é do usuário e descartável.
 *
 * O erro é o MESMO para "código inexistente" e "já são amigos": mensagem distinta
 * vazaria informação sobre terceiros.
 */
export const sendFriendRequest = guarded(
  {
    action: 'sendFriendRequest',
    schema: sendFriendRequestInput,
    requireVerified: true,
    limit: { max: 20, windowSec: 3600 }, // anti-varredura de espaço de códigos
  },
  async (data, ctx) => {
    const q = await db
      .collection('users')
      .where('friendCode', '==', data.friendCode)
      .limit(1)
      .get();

    if (q.empty) {
      await audit('friend_code_miss', ctx.uid, 'info', {});
      throw Err.notFound();
    }

    const target = q.docs[0]!;
    if (target.id === ctx.uid) throw Err.invalidArg('SELF_FRIEND');

    const pairId = [ctx.uid, target.id].sort().join('_');
    const existing = await db.collection('friendships').doc(pairId).get();
    if (existing.exists) throw Err.notFound(); // mesmo erro de propósito

    const reqId = randomUUID();
    await db.collection('friendRequests').doc(reqId).create({
      from: ctx.uid,
      to: target.id,
      pairId,
      status: 'pending',
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      schemaVersion: SCHEMA_VERSION,
    });

    return { requestId: reqId };
  },
);

export const respondFriendRequest = guarded(
  { action: 'respondFriendRequest', schema: respondFriendRequestInput, requireVerified: true, limit: { max: 50, windowSec: 3600 } },
  async (data, ctx) => {
    const ref = db.collection('friendRequests').doc(data.requestId);

    return db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists || snap.get('to') !== ctx.uid) throw Err.notFound();
      if (snap.get('status') !== 'pending') throw Err.conflict('ALREADY_RESOLVED');

      tx.update(ref, {
        status: data.accept ? 'accepted' : 'declined',
        updatedAt: FieldValue.serverTimestamp(),
      });

      if (data.accept) {
        const pairId = snap.get('pairId') as string;
        tx.set(db.collection('friendships').doc(pairId), {
          members: [snap.get('from'), ctx.uid],
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
          schemaVersion: SCHEMA_VERSION,
        });
      }

      return { accepted: data.accept };
    });
  },
);

/**
 * Troca de username. Precisa ser Callable (e não escrita direta com Rules) porque
 * exige reserva ATÔMICA em duas coleções: liberar o antigo e tomar o novo.
 * Rules não fazem isso; transação faz.
 */
export const updateUsername = guarded(
  { action: 'updateUsername', schema: updateUsernameInput, limit: { max: 3, windowSec: 86400 } },
  async (data, ctx) => {
    const lower = data.username.toLowerCase();
    const newRef = db.collection('usernames').doc(lower);
    const userRef = db.collection('users').doc(ctx.uid);

    await db.runTransaction(async (tx) => {
      const [taken, userSnap] = await txGetAll(tx, newRef, userRef);
      if (taken.exists && taken.get('uid') !== ctx.uid) throw Err.conflict('USERNAME_TAKEN');

      const old = userSnap.get('username') as string | undefined;
      if (old && old.toLowerCase() !== lower) {
        tx.delete(db.collection('usernames').doc(old.toLowerCase()));
      }

      tx.set(newRef, { uid: ctx.uid, createdAt: FieldValue.serverTimestamp() });
      tx.update(userRef, { username: data.username, updatedAt: FieldValue.serverTimestamp() });
    });

    return { username: data.username };
  },
);
