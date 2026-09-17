import { HttpsError } from 'firebase-functions/v2/https';

/**
 * Códigos de erro do contrato público. O cliente faz switch nestes valores.
 * Mensagens são genéricas de propósito: não revelam estado interno nem existência
 * de recursos de terceiros (anti-enumeração).
 */
export const Err = {
  unauthenticated: () => new HttpsError('unauthenticated', 'AUTH_REQUIRED'),
  appCheck: () => new HttpsError('failed-precondition', 'APP_CHECK_REQUIRED'),
  emailNotVerified: () => new HttpsError('failed-precondition', 'EMAIL_NOT_VERIFIED'),
  invalidArg: (detail: string) => new HttpsError('invalid-argument', detail),
  rateLimited: (retryAfterSec: number) =>
    new HttpsError('resource-exhausted', 'RATE_LIMITED', { retryAfterSec }),
  notFound: () => new HttpsError('not-found', 'NOT_FOUND'),
  locked: (reason: string) => new HttpsError('permission-denied', reason),
  conflict: (detail: string) => new HttpsError('aborted', detail),
  /** Contenção transitória no Firestore. `unavailable` mantém o item no outbox do cliente. */
  contention: () => new HttpsError('unavailable', 'CONTENTION'),
  internal: () => new HttpsError('internal', 'INTERNAL'),
} as const;
