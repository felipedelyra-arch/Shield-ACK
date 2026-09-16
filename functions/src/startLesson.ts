import { db, FieldValue, SCHEMA_VERSION, getAll } from './lib/init';
import { guarded } from './lib/guard';
import { startLessonInput } from './domain/schemas';
import { Err } from './lib/errors';
import { audit } from './lib/audit';
import { currentHearts, MAX_HEARTS, nextRegenAt } from './lib/hearts';

/**
 * Autoriza o início de uma lição. O app DESENHA a trilha a partir do catálogo;
 * quem AUTORIZA é esta function. Um cliente modificado que pule o desbloqueio
 * na UI ainda esbarra aqui — e o progresso dele não avança.
 */
export const startLesson = guarded(
  { action: 'startLesson', schema: startLessonInput, limit: { max: 60, windowSec: 300 } },
  async (data, ctx) => {
    const { lessonId } = data;

    const lessonRef = db.collection('lessons').doc(lessonId);
    const userRef = db.collection('users').doc(ctx.uid);
    const progressRef = userRef.collection('progress').doc(lessonId);

    const [lessonSnap, userSnap, progressSnap] = await getAll(lessonRef, userRef, progressRef);
    if (!lessonSnap.exists) throw Err.notFound();

    const now = new Date();
    const hearts = currentHearts(userSnap.get('hearts') ?? MAX_HEARTS, userSnap.get('heartsUpdatedAt') ?? null, now);
    if (hearts <= 0) {
      throw Err.locked('NO_HEARTS');
    }

    // --- Desbloqueio sequencial, validado no servidor.
    const order = lessonSnap.get('order') as number;
    const moduleId = lessonSnap.get('moduleId') as string;

    if (order > 0) {
      const moduleRef = db.collection('tracks').doc(lessonSnap.get('trackId')).collection('modules').doc(moduleId);
      const moduleSnap = await moduleRef.get();
      const lessonIds = (moduleSnap.get('lessonIds') as string[]) ?? [];
      const prevId = lessonIds[order - 1];

      if (prevId) {
        const prev = await userRef.collection('progress').doc(prevId).get();
        if (prev.get('status') !== 'completed') {
          await audit('lesson_unlock_bypass_attempt', ctx.uid, 'warn', { lessonId, prevId });
          throw Err.locked('PREVIOUS_LESSON_INCOMPLETE');
        }
      }
    }

    // Idempotente por natureza: chamar duas vezes só atualiza updatedAt.
    await progressRef.set(
      {
        trackId: lessonSnap.get('trackId'),
        moduleId,
        status: progressSnap.get('status') === 'completed' ? 'completed' : 'in_progress',
        startedAt: progressSnap.exists ? progressSnap.get('startedAt') : FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        schemaVersion: SCHEMA_VERSION,
      },
      { merge: true },
    );

    return {
      lessonId,
      resumeAtSec: (progressSnap.get('lastPositionSec') as number) ?? 0,
      hearts,
      nextHeartAt: nextRegenAt(hearts, userSnap.get('heartsUpdatedAt') ?? null, now)?.toISOString() ?? null,
      durationSec: lessonSnap.get('durationSec') ?? 0,
    };
  },
);
