import { z } from 'zod';
import { db, FieldValue, SCHEMA_VERSION } from '../lib/init';
import { guarded } from '../lib/guard';
import { audit } from '../lib/audit';
import { Err } from '../lib/errors';
import { docId, uid as uidSchema } from '../domain/schemas';

/**
 * Gera o documento agregado `catalog/{version}` — a peça que faz a tela de trilha
 * custar 1 leitura em vez de N (docs/00-CORRECOES.md C2).
 *
 * Também é o portão de qualidade do conteúdo: antes de publicar, VERIFICA que
 * nenhum documento de questão contém campo de gabarito. Rules protegem answerKeys,
 * mas não impedem alguém de colar a resposta dentro do enunciado por engano.
 */
const FORBIDDEN_FIELDS = ['correct', 'answer', 'correctIndex', 'solution', 'gabarito'];

export const publishCatalog = guarded(
  { action: 'publishCatalog', schema: z.object({}), requireRole: 'admin', limit: { max: 10, windowSec: 3600 } },
  async (_data, ctx) => {
    const tracks = await db.collection('tracks').orderBy('order').limit(200).get();
    const out: unknown[] = [];
    const leaks: string[] = [];

    for (const t of tracks.docs) {
      const modules = await t.ref.collection('modules').orderBy('order').limit(100).get();
      const mOut = [];

      for (const m of modules.docs) {
        const lessonIds = (m.get('lessonIds') as string[]) ?? [];
        const lessons = lessonIds.length
          ? await db.getAll(...lessonIds.map((id) => db.collection('lessons').doc(id)))
          : [];

        for (const l of lessons) {
          if (!l.exists) continue;
          const qs = await l.ref.collection('questions').limit(50).get();
          for (const q of qs.docs) {
            const keys = Object.keys(q.data());
            const bad = keys.filter((k) => FORBIDDEN_FIELDS.includes(k));
            if (bad.length) leaks.push(`${l.id}/${q.id}:${bad.join(',')}`);
          }
        }

        mOut.push({
          id: m.id,
          title: m.get('title'),
          order: m.get('order'),
          lessons: lessons
            .filter((l) => l.exists)
            .map((l) => ({
              id: l.id,
              title: l.get('title'),
              order: l.get('order'),
              durationSec: l.get('durationSec'),
              xpReward: l.get('xpReward'),
              thumbUrl: l.get('thumbUrl') ?? null,
              // videoAssetId NÃO entra no catálogo. URL só via getLessonPlayback().
            })),
        });
      }

      out.push({ id: t.id, title: t.get('title'), level: t.get('level'), order: t.get('order'), modules: mOut });
    }

    if (leaks.length) {
      await audit('catalog_publish_blocked_leak', ctx.uid, 'critical', { count: leaks.length });
      throw Err.invalidArg(`ANSWER_LEAK_IN_QUESTIONS:${leaks.slice(0, 5).join('|')}`);
    }

    const version = `v${Date.now()}`;
    await db.collection('catalog').doc(version).create({
      tracks: out,
      publishedBy: ctx.uid,
      createdAt: FieldValue.serverTimestamp(),
      schemaVersion: SCHEMA_VERSION,
    });

    await audit('catalog_published', ctx.uid, 'info', { version, tracks: out.length });
    // O cliente descobre a nova versão pelo Remote Config (catalog_version),
    // não por listener — listener em catálogo cobraria a cada publicação × usuários.
    return { version, hint: 'Atualize remote_config.catalog_version para ' + version };
  },
);

/** Custom claims só aqui. O cliente NUNCA define papel. */
export const setUserRole = guarded(
  {
    action: 'setUserRole',
    schema: z.object({ targetUid: uidSchema, role: z.enum(['student', 'teacher', 'admin']) }),
    requireRole: 'admin',
    limit: { max: 20, windowSec: 3600 },
  },
  async (data, ctx) => {
    const { auth } = await import('../lib/init');
    await auth.setCustomUserClaims(data.targetUid, { role: data.role });
    // Claim antiga vive no ID token até expirar (1h). Revogar força refresh agora.
    await auth.revokeRefreshTokens(data.targetUid);
    await audit('role_changed', ctx.uid, 'critical', { targetUid: data.targetUid, role: data.role });
    return { ok: true };
  },
);

export const _schemas = { docId };
