import { z } from 'zod';

/**
 * Idempotency key. Exigimos UUID v4 por dois motivos:
 *  - é usada como ID de documento em xpEvents => precisa ser aleatória para não
 *    criar hotspot de escrita (chaves sequenciais concentram no mesmo tablet);
 *  - impede que o cliente escolha uma chave previsível e sobrescreva a de outro fluxo.
 */
export const idempotencyKey = z
  .string()
  .regex(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i, 'uuidv4');

/**
 * IDs de documento. A whitelist de charset é o que impede NoSQL path injection:
 * sem isso, um lessonId `../../answerKeys/q1` viraria um path válido em
 * db.doc(`lessons/${id}`). NUNCA concatenar entrada do cliente em path sem passar por aqui.
 */
export const docId = z.string().min(1).max(64).regex(/^[A-Za-z0-9_-]+$/, 'docId');

export const uid = z.string().min(20).max(128).regex(/^[A-Za-z0-9]+$/, 'uid');

export const answerValue = z.union([
  z.number().int().min(0).max(9),        // múltipla escolha: índice da opção
  z.boolean(),                            // verdadeiro/falso
  z.array(z.number().int().min(0).max(19)).max(20), // ordenação / associação
  z.string().max(200),                    // preenchimento de terminal
]);

export const startLessonInput = z.object({
  lessonId: docId,
});

export const submitQuizInput = z.object({
  lessonId: docId,
  idempotencyKey,
  /** Tempo medido no cliente. É SINAL, não verdade — usado só para anti-cheat. */
  clientElapsedMs: z.number().int().min(0).max(3_600_000),
  answers: z
    .array(z.object({ questionId: docId, value: answerValue }))
    .min(1)
    .max(20),
});

export const getLessonPlaybackInput = z.object({
  lessonId: docId,
});

export const syncWatchProgressInput = z.object({
  /** Lote do outbox. Teto de 50 para caber num batch e não estourar o timeout. */
  items: z
    .array(
      z.object({
        lessonId: docId,
        positionSec: z.number().int().min(0).max(86_400),
        watchedDeltaSec: z.number().int().min(0).max(3_600),
        clientTs: z.number().int().positive(),
      }),
    )
    .min(1)
    .max(50),
});

export const registerDeviceInput = z.object({
  fcmToken: z.string().min(50).max(4096),
  platform: z.enum(['android', 'ios']),
  /** IANA tz. Validado contra Intl no handler — regex sozinha não basta. */
  tz: z.string().min(3).max(64).regex(/^[A-Za-z_]+\/[A-Za-z_+-]+$/),
  appVersion: z.string().max(32),
});

export const sendFriendRequestInput = z.object({
  friendCode: z.string().length(8).regex(/^[A-Z0-9]{8}$/),
});

export const respondFriendRequestInput = z.object({
  requestId: docId,
  accept: z.boolean(),
});

export const createDuelInput = z.object({
  opponentUid: uid,
  trackId: docId,
  idempotencyKey,
});

export const respondDuelInput = z.object({
  duelId: docId,
  accept: z.boolean(),
});

export const submitDuelRoundInput = z.object({
  duelId: docId,
  round: z.number().int().min(0).max(9),
  idempotencyKey,
  clientElapsedMs: z.number().int().min(0).max(600_000),
  answers: z.array(z.object({ questionId: docId, value: answerValue })).min(1).max(10),
});

export const updateUsernameInput = z.object({
  username: z.string().min(3).max(20).regex(/^[a-z0-9_]+$/, 'username'),
});
