import { db, FieldValue, SCHEMA_VERSION } from './init';
import { randomUUID } from 'node:crypto';

export type Severity = 'info' | 'warn' | 'critical';

/**
 * Log de auditoria append-only. ID aleatório para não criar hotspot de escrita.
 * NUNCA gravar PII aqui: sem e-mail, sem nome, sem conteúdo de resposta.
 * Consulta é feita no BigQuery (extension de streaming), nunca no Firestore.
 */
export async function audit(
  action: string,
  actorUid: string | null,
  severity: Severity,
  meta: Record<string, string | number | boolean> = {},
): Promise<void> {
  try {
    await db.collection('auditLogs').doc(randomUUID()).create({
      action,
      actorUid,
      severity,
      meta,
      createdAt: FieldValue.serverTimestamp(),
      schemaVersion: SCHEMA_VERSION,
    });
  } catch (e) {
    // Auditoria nunca pode derrubar a operação de negócio. Falha vira log estruturado.
    console.error(JSON.stringify({ severity: 'ERROR', msg: 'audit_write_failed', action }));
  }
}
