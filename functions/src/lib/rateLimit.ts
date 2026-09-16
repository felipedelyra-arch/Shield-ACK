import { db, FieldValue, Timestamp } from './init';
import { Err } from './errors';
import { audit } from './audit';

export interface Limit {
  /** Máximo de chamadas na janela. */
  max: number;
  /** Tamanho da janela em segundos. */
  windowSec: number;
}

/**
 * Rate limit por (uid, action) em janela fixa.
 *
 * Por que documento único por usuário é seguro aqui: o limite de 1 escrita/segundo
 * sustentada do Firestore é POR DOCUMENTO, e este documento é exclusivo de um usuário.
 * Um único usuário passando de 1 req/s nesta chave já é, por definição, o caso que
 * queremos bloquear. Não existe contenção entre usuários.
 *
 * TTL: campo `expireAt` com política de TTL configurada na coleção `rateLimits`.
 * Sem TTL a coleção cresce para sempre.
 */
export async function enforceRateLimit(uid: string, action: string, limit: Limit): Promise<void> {
  const ref = db.collection('rateLimits').doc(`${uid}__${action}`);
  const now = Date.now();

  const exceeded = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const windowStart: number = snap.exists ? (snap.get('windowStart') ?? 0) : 0;
    const count: number = snap.exists ? (snap.get('count') ?? 0) : 0;

    const windowExpired = now - windowStart >= limit.windowSec * 1000;

    if (windowExpired) {
      tx.set(ref, {
        windowStart: now,
        count: 1,
        expireAt: Timestamp.fromMillis(now + limit.windowSec * 2000),
      });
      return 0;
    }

    if (count >= limit.max) {
      return Math.ceil((windowStart + limit.windowSec * 1000 - now) / 1000);
    }

    tx.update(ref, { count: FieldValue.increment(1) });
    return 0;
  });

  if (exceeded > 0) {
    await audit('rate_limit_hit', uid, 'warn', { action, retryAfterSec: exceeded });
    throw Err.rateLimited(exceeded);
  }
}
