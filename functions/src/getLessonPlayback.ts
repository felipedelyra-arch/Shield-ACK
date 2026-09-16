import { createHmac, randomUUID } from 'node:crypto';
import { defineSecret } from 'firebase-functions/params';
import { db, getAll } from './lib/init';
import { guarded } from './lib/guard';
import { getLessonPlaybackInput } from './domain/schemas';
import { Err } from './lib/errors';
import { audit } from './lib/audit';

// Segredo do provedor de vídeo. Vive no Secret Manager, NUNCA no repositório,
// nunca em functions.config(), nunca no app. Deploy: firebase functions:secrets:set
const STREAM_SIGNING_KEY = defineSecret('STREAM_SIGNING_KEY');
const STREAM_KEY_ID = defineSecret('STREAM_KEY_ID');

/** TTL curto de propósito: é a principal defesa contra compartilhamento de link. */
const TOKEN_TTL_SEC = 120;

/**
 * Emite URL HLS assinada. A Cloud Function é o BFF: o app nunca conhece a chave
 * do provedor de vídeo e nunca fala direto com ele para autorizar.
 *
 * LIMITAÇÃO CONHECIDA (docs/00-CORRECOES.md C6): o token NÃO é criptograficamente
 * vinculado ao uid — o provedor de vídeo não conhece o Firebase Auth. O uid vai
 * como claim assinada para AUDITORIA. O controle de acesso real é TTL + rate limit.
 * Redistribuição dentro da janela de 120s é risco residual aceito.
 */
export const getLessonPlayback = guarded(
  {
    action: 'getLessonPlayback',
    schema: getLessonPlaybackInput,
    // Teto agressivo: 20 emissões / 10 min. Uma sessão normal precisa de 1–3.
    // Acima disso é scraping de catálogo.
    limit: { max: 20, windowSec: 600 },
    options: { secrets: [STREAM_SIGNING_KEY, STREAM_KEY_ID] },
  },
  async (data, ctx) => {
    const { lessonId } = data;

    const [lessonSnap, progressSnap] = await getAll(
      db.collection('lessons').doc(lessonId),
      db.collection('users').doc(ctx.uid).collection('progress').doc(lessonId),
    );

    if (!lessonSnap.exists) throw Err.notFound();

    // Sem startLesson bem-sucedido não há playback. Fecha o atalho de pedir a URL direto.
    if (!progressSnap.exists || progressSnap.get('status') === 'locked') {
      await audit('playback_without_start', ctx.uid, 'warn', { lessonId });
      throw Err.locked('LESSON_LOCKED');
    }

    const videoId = lessonSnap.get('videoAssetId') as string;
    const exp = Math.floor(Date.now() / 1000) + TOKEN_TTL_SEC;
    const jti = randomUUID();

    // JWT de stream (formato Cloudflare Stream signed URL).
    const header = { alg: 'RS256', kid: STREAM_KEY_ID.value() };
    const payload = {
      sub: videoId,
      kid: STREAM_KEY_ID.value(),
      exp,
      nbf: Math.floor(Date.now() / 1000) - 5,
      jti,
      // Claim de auditoria, NÃO de autorização. Ver docs/00-CORRECOES.md C6.
      shieldack_uid: ctx.uid,
      accessRules: [
        { type: 'ip.geoip.country', country: ['BR', 'PT'], action: 'allow' },
        { type: 'any', action: 'block' },
      ],
    };

    const b64 = (o: unknown) =>
      Buffer.from(JSON.stringify(o)).toString('base64url');
    const unsigned = `${b64(header)}.${b64(payload)}`;
    const signature = createHmac('sha256', STREAM_SIGNING_KEY.value())
      .update(unsigned)
      .digest('base64url');
    const token = `${unsigned}.${signature}`;

    // Toda emissão é auditada. É assim que se detecta uma conta revendendo acesso:
    // N emissões distintas por hora correlacionadas a N IPs.
    await audit('playback_issued', ctx.uid, 'info', { lessonId, jti, ttl: TOKEN_TTL_SEC });

    return {
      hlsUrl: `https://videodelivery.net/${token}/manifest/video.m3u8`,
      expiresAt: exp * 1000,
      resumeAtSec: (progressSnap.get('lastPositionSec') as number) ?? 0,
    };
  },
);
