import { beforeUserCreated, beforeUserSignedIn } from 'firebase-functions/v2/identity';
import { randomBytes } from 'node:crypto';
import { db, auth, FieldValue, SCHEMA_VERSION, REGION } from '../lib/init';
import { audit } from '../lib/audit';
import { HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';
import { guarded } from '../lib/guard';

const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // sem I/O/0/1 — ambíguos ao ditar

function friendCode(): string {
  const b = randomBytes(8);
  return [...b].map((n) => CODE_ALPHABET[n % CODE_ALPHABET.length]).join('');
}

/**
 * Blocking function (Identity Platform). Roda ANTES da conta existir.
 * É aqui que se barra criação automatizada em massa — depois do onCreate já é tarde,
 * a conta existe e consome cota.
 */
export const beforeCreate = beforeUserCreated({ region: REGION }, async (event) => {
  const user = event.data;
  if (!user) return;

  // Provedores permitidos. Qualquer outro (anônimo, telefone, SAML não previsto) é negado.
  const providers = user.providerData.map((p) => p.providerId);
  const allowed = ['google.com', 'password'];
  if (providers.length > 0 && !providers.some((p) => allowed.includes(p))) {
    await audit('signup_blocked_provider', null, 'warn', { providers: providers.join(',') });
    throw new HttpsError('permission-denied', 'PROVIDER_NOT_ALLOWED');
  }

  // Papel default vem daqui, não do cliente. Cliente NUNCA define claim.
  return {
    customClaims: { role: 'student' },
  };
});

export const beforeSignIn = beforeUserSignedIn({ region: REGION }, async (event) => {
  const user = event.data;
  if (!user) return;

  const flag = await db.collection('users').doc(user.uid).get();
  if (flag.exists && flag.get('blocked') === true) {
    await audit('signin_blocked_account', user.uid, 'critical', {});
    throw new HttpsError('permission-denied', 'ACCOUNT_BLOCKED');
  }
  return;
});

/**
 * Criação do perfil. O cliente NÃO cria users/{uid} — Rules negam create.
 * Isto garante que xp, level, hearts e friendCode nascem com valores do servidor.
 */
export async function provisionUser(uid: string, displayName: string | null, photoUrl: string | null) {
  const ref = db.collection('users').doc(uid);
  if ((await ref.get()).exists) return;

  // Colisão de código é improvável (32^8 ≈ 1.1e12) mas não impossível: retry limitado.
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = friendCode();
    try {
      await db.runTransaction(async (tx) => {
        const codeRef = db.collection('usernames').doc(`code:${code}`);
        if ((await tx.get(codeRef)).exists) throw new Error('collision');
        tx.create(codeRef, { uid });
        tx.create(ref, {
          displayName: displayName?.slice(0, 40) ?? 'Aprendiz',
          photoUrl: photoUrl ?? null,
          friendCode: code,
          xp: 0,
          level: 1,
          hearts: 5,
          heartsUpdatedAt: FieldValue.serverTimestamp(),
          streakDays: 0,
          lastStudyDay: null,
          tz: 'America/Sao_Paulo',
          notifyInactivity: true,
          blocked: false,
          lastActiveAt: FieldValue.serverTimestamp(),
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
          schemaVersion: SCHEMA_VERSION,
        });
      });
      return;
    } catch (e) {
      if (attempt === 4) throw e;
    }
  }
}

/** Revoga refresh tokens — logout global e resposta a comprometimento. */
export async function revokeAllSessions(uid: string, reason: string) {
  await auth.revokeRefreshTokens(uid);
  await audit('sessions_revoked', uid, 'critical', { reason });
}

/**
 * Chamada pelo app logo após o primeiro login bem-sucedido.
 *
 * Por que Callable e não trigger `auth.user().onCreate`: o trigger de Auth é da 1ª
 * geração e obriga a misturar duas gerações no mesmo codebase. Com blocking functions
 * (Identity Platform) já em uso, um Callable idempotente no primeiro login é mais
 * simples e testável no emulador. Chamar N vezes é inofensivo — o primeiro `get` sai.
 */
export const bootstrapProfile = guarded(
  { action: 'bootstrapProfile', schema: z.object({}), limit: { max: 10, windowSec: 3600 } },
  async (_d, ctx) => {
    const user = await auth.getUser(ctx.uid);
    await provisionUser(ctx.uid, user.displayName ?? null, user.photoURL ?? null);

    // Dados sensíveis vão para /private — nunca no doc público lido por amigos.
    await db.collection('users').doc(ctx.uid).collection('private').doc('profile').set(
      {
        email: user.email ?? null,
        notifPrefs: { inactivity: true, streak: true, overtaken: true, duel: true },
        quietHours: { start: 22, end: 8 },
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    const snap = await db.collection('users').doc(ctx.uid).get();
    return { friendCode: snap.get('friendCode'), created: true };
  },
);
