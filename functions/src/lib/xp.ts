import { db, FieldValue, SCHEMA_VERSION, txGetAll } from './init';
import { Timestamp } from 'firebase-admin/firestore';

export type XpReason = 'lesson_complete' | 'quiz_perfect' | 'duel_win' | 'streak_bonus' | 'admin_grant';

export interface XpAward {
  uid: string;
  /** ID do evento == idempotencyKey. É ISTO que torna o retry seguro, não um `if exists`. */
  eventId: string;
  amount: number;
  reason: XpReason;
  ref: string;
}

export interface XpResult {
  awarded: number;
  /** true quando o evento já existia — retry. Cliente deve tratar como sucesso. */
  duplicate: boolean;
  totalXp: number;
  level: number;
}

/** Curva de nível: 100 * n^1.5. Parametrizável por Remote Config no cliente só para EXIBIÇÃO. */
export function levelForXp(xp: number): number {
  let level = 1;
  while (Math.floor(100 * Math.pow(level, 1.5)) <= xp) level++;
  return level;
}

export function periodId(d: Date = new Date()): string {
  // ISO week — usado para ligas semanais e agregação de ranking.
  const t = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7));
  const yearStart = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
  const week = Math.ceil(((t.getTime() - yearStart.getTime()) / 86400000 + 1) / 7);
  return `${t.getUTCFullYear()}-W${String(week).padStart(2, '0')}`;
}

/**
 * Grava XP no ledger e atualiza o cache em users/{uid}.xp — atomicamente.
 *
 * Invariante: o ledger é a verdade; users/{uid}.xp é derivado.
 * Se as duas divergirem, `reconcileXp` (agendada) corrige pelo ledger e audita.
 *
 * A idempotência vem de `create()` num documento cujo ID é a idempotencyKey:
 * a segunda chamada falha com ALREADY_EXISTS dentro da transação e nós devolvemos
 * duplicate=true. Não há janela de corrida — diferente de um `get` seguido de `set`.
 */
export async function awardXp(a: XpAward): Promise<XpResult> {
  const userRef = db.collection('users').doc(a.uid);
  const eventRef = userRef.collection('xpEvents').doc(a.eventId);

  return db.runTransaction(async (tx) => {
    const [userSnap, eventSnap] = await txGetAll(tx, userRef, eventRef);
    return stageXp(tx, a, userSnap.get('xp') ?? 0, eventSnap.exists);
  });
}

/**
 * Parte transacional de `awardXp`, para quem já está numa transação maior.
 * Pré-condição: `users/{uid}` e `xpEvents/{eventId}` foram lidos em `tx`.
 */
export function stageXp(
  tx: FirebaseFirestore.Transaction,
  a: XpAward,
  currentXp: number,
  eventExists: boolean,
): XpResult {
  if (eventExists) {
    return { awarded: 0, duplicate: true, totalXp: currentXp, level: levelForXp(currentXp) };
  }

  const totalXp = currentXp + a.amount;
  const level = levelForXp(totalXp);
  const userRef = db.collection('users').doc(a.uid);

  tx.create(userRef.collection('xpEvents').doc(a.eventId), {
    amount: a.amount,
    reason: a.reason,
    ref: a.ref,
    periodId: periodId(),
    createdAt: Timestamp.now(),
    schemaVersion: SCHEMA_VERSION,
  });

  tx.update(userRef, {
    xp: totalXp,
    level,
    lastActiveAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  return { awarded: a.amount, duplicate: false, totalXp, level };
}
