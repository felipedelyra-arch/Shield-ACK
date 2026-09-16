import { z } from 'zod';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { db, auth, FieldValue, REGION } from './lib/init';
import { guarded } from './lib/guard';
import { audit } from './lib/audit';
import { getStorage } from 'firebase-admin/storage';

/**
 * LGPD art. 18: titular tem direito a eliminação e a portabilidade.
 * A exclusão é assíncrona (trigger) porque apagar subcoleções pode passar do
 * timeout da Callable; a Callable só registra o pedido e responde na hora.
 */
export const requestAccountDeletion = guarded(
  { action: 'requestAccountDeletion', schema: z.object({ confirm: z.literal('EXCLUIR') }), limit: { max: 3, windowSec: 86400 } },
  async (_d, ctx) => {
    await db.collection('deletionRequests').doc(ctx.uid).set({
      status: 'pending',
      requestedAt: FieldValue.serverTimestamp(),
    });
    await audit('deletion_requested', ctx.uid, 'critical', {});
    return { status: 'pending' };
  },
);

export const processDeletion = onDocumentCreated(
  { document: 'deletionRequests/{uid}', region: REGION, timeoutSeconds: 540 },
  async (event) => {
    const uid = event.params.uid;

    // 1. Revoga sessões primeiro: impede que o app continue escrevendo durante a purga.
    await auth.revokeRefreshTokens(uid).catch(() => undefined);

    // 2. Firestore: subcoleções + doc raiz.
    await db.recursiveDelete(db.collection('users').doc(uid));

    // 3. Amizades, duelos, devices, reservas de username.
    const writer = db.bulkWriter();
    for (const col of ['friendships', 'friendRequests', 'devices', 'duels']) {
      const field = col === 'friendships' || col === 'duels' ? 'members' : 'uid';
      const q =
        col === 'friendships'
          ? db.collection(col).where('members', 'array-contains', uid)
          : col === 'duels'
            ? db.collection(col).where('players', 'array-contains', uid)
            : col === 'friendRequests'
              ? db.collection(col).where('from', '==', uid)
              : db.collection(col).where(field, '==', uid);
      const snap = await q.limit(500).get();
      snap.docs.forEach((d) => void writer.delete(d.ref));
    }
    await writer.close();

    // 4. Storage (avatar).
    await getStorage().bucket().deleteFiles({ prefix: `avatars/${uid}/` }).catch(() => undefined);

    // 5. Auth por último: se algo acima falhar, a conta ainda existe para retry.
    await auth.deleteUser(uid).catch(() => undefined);

    await db.collection('deletionRequests').doc(uid).set(
      { status: 'done', completedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
    // auditLogs guarda o uid pseudonimizado como prova de cumprimento — permitido
    // pelo art. 16, I (cumprimento de obrigação legal). Sem PII.
    await audit('deletion_completed', null, 'critical', { uidHash: uid.slice(0, 6) });
  },
);

export const exportMyData = guarded(
  { action: 'exportMyData', schema: z.object({}), limit: { max: 3, windowSec: 86400 } },
  async (_d, ctx) => {
    const [profile, priv, progress, xpEvents] = await Promise.all([
      db.collection('users').doc(ctx.uid).get(),
      db.collection('users').doc(ctx.uid).collection('private').doc('profile').get(),
      db.collection('users').doc(ctx.uid).collection('progress').limit(1000).get(),
      db.collection('users').doc(ctx.uid).collection('xpEvents').orderBy('createdAt', 'desc').limit(1000).get(),
    ]);

    await audit('data_exported', ctx.uid, 'info', {});
    return {
      profile: profile.data() ?? null,
      private: priv.data() ?? null,
      progress: progress.docs.map((d) => ({ lessonId: d.id, ...d.data() })),
      xpEvents: xpEvents.docs.map((d) => ({ id: d.id, ...d.data() })),
    };
  },
);
