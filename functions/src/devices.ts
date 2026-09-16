import { createHash } from 'node:crypto';
import { db, FieldValue, SCHEMA_VERSION } from './lib/init';
import { guarded } from './lib/guard';
import { registerDeviceInput } from './domain/schemas';
import { isValidTimeZone } from './lib/streak';
import { Err } from './lib/errors';

/**
 * Registro de device para push.
 *
 * O ID do documento é o HASH do token, não o token: o token do FCM é longo e
 * contém caracteres inválidos para ID de documento, e hashear evita expor o
 * token na chave de um documento legível. O token em si fica no campo.
 */
export const registerDevice = guarded(
  { action: 'registerDevice', schema: registerDeviceInput, limit: { max: 20, windowSec: 3600 } },
  async (data, ctx) => {
    if (!isValidTimeZone(data.tz)) throw Err.invalidArg('INVALID_TZ');

    const tokenId = createHash('sha256').update(data.fcmToken).digest('hex').slice(0, 40);

    await db.collection('devices').doc(tokenId).set(
      {
        uid: ctx.uid,
        fcmToken: data.fcmToken,
        platform: data.platform,
        tz: data.tz,
        appVersion: data.appVersion,
        lastSeenAt: FieldValue.serverTimestamp(),
        createdAt: FieldValue.serverTimestamp(),
        schemaVersion: SCHEMA_VERSION,
      },
      { merge: true },
    );

    // tz do usuário alimenta streak e janela de silêncio das notificações.
    await db.collection('users').doc(ctx.uid).set({ tz: data.tz }, { merge: true });

    return { tokenId };
  },
);
