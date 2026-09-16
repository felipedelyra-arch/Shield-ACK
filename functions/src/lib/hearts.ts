import { Timestamp } from 'firebase-admin/firestore';

export const MAX_HEARTS = 5;
export const REGEN_MINUTES = 30;

/**
 * Vidas são derivadas de (heartsAtLastWrite, heartsUpdatedAt), NUNCA de um timer.
 * Um timer local é trivial de burlar mudando o relógio do aparelho; um delta de
 * timestamp do servidor não é. Esta função é pura e testável.
 */
export function currentHearts(stored: number, updatedAt: Timestamp | null, now: Date): number {
  if (stored >= MAX_HEARTS || !updatedAt) return Math.min(stored, MAX_HEARTS);
  const elapsedMin = (now.getTime() - updatedAt.toMillis()) / 60000;
  if (elapsedMin < 0) return stored; // relógio do servidor nunca anda para trás; guarda defensiva
  const regen = Math.floor(elapsedMin / REGEN_MINUTES);
  return Math.min(MAX_HEARTS, stored + regen);
}

export function nextRegenAt(hearts: number, updatedAt: Timestamp | null, now: Date): Date | null {
  if (hearts >= MAX_HEARTS || !updatedAt) return null;
  const base = updatedAt.toMillis();
  const elapsed = now.getTime() - base;
  const steps = Math.floor(elapsed / (REGEN_MINUTES * 60000)) + 1;
  return new Date(base + steps * REGEN_MINUTES * 60000);
}
