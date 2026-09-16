import { db, FieldValue, SCHEMA_VERSION } from './lib/init';
import { guarded } from './lib/guard';
import { syncWatchProgressInput } from './domain/schemas';

/**
 * Recebe o LOTE de heartbeats acumulados pelo outbox local.
 *
 * Por que em lote: um heartbeat a cada 10s numa aula de 12 min são 72 escritas.
 * Com 10k usuários/dia isso é 720k writes/dia só de watch-time — ~R$ 60/dia, pelo nada.
 * Em lote de 50 vira ~1.5 write por aula.
 *
 * Idempotência: posição é MONOTÔNICA (max), watchedSec é incremento acumulado no
 * cliente e só é aplicado se o lote for novo — o cliente descarta o lote após o ack.
 * Reenvio do mesmo lote infla watchedSec no máximo uma vez; como watchedSec é
 * métrica e não dinheiro, aceitamos essa imprecisão em vez de pagar um ack por item.
 */
export const syncWatchProgress = guarded(
  { action: 'syncWatchProgress', schema: syncWatchProgressInput, limit: { max: 60, windowSec: 600 } },
  async (data, ctx) => {
    // Consolida por lessonId: o lote pode ter 30 heartbeats da mesma aula.
    const byLesson = new Map<string, { positionSec: number; watchedDeltaSec: number }>();
    for (const item of data.items) {
      const cur = byLesson.get(item.lessonId);
      byLesson.set(item.lessonId, {
        positionSec: Math.max(cur?.positionSec ?? 0, item.positionSec),
        watchedDeltaSec: (cur?.watchedDeltaSec ?? 0) + item.watchedDeltaSec,
      });
    }

    const progressCol = db.collection('users').doc(ctx.uid).collection('progress');

    // Uma transação por lição (na prática 1 por chamada): precisamos de max() em
    // lastPositionSec, que um batch não oferece, e de increment() em watchedSec.
    await Promise.all(
      [...byLesson].map(([lessonId, v]) =>
        db.runTransaction(async (tx) => {
          const ref = progressCol.doc(lessonId);
          const snap = await tx.get(ref);
          const prev = (snap.get('lastPositionSec') as number) ?? 0;
          tx.set(
            ref,
            {
              // Monotônico: dois dispositivos assistindo convergem para o mais adiantado.
              lastPositionSec: Math.max(prev, v.positionSec),
              watchedSec: FieldValue.increment(v.watchedDeltaSec),
              updatedAt: FieldValue.serverTimestamp(),
              schemaVersion: SCHEMA_VERSION,
            },
            { merge: true },
          );
        }),
      ),
    );

    await db.collection('users').doc(ctx.uid).set(
      { lastActiveAt: FieldValue.serverTimestamp() },
      { merge: true },
    );

    return { accepted: data.items.length, lessons: byLesson.size };
  },
);
