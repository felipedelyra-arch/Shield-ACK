import { initializeApp, getApps } from 'firebase-admin/app';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import { getDatabase } from 'firebase-admin/database';
import { getMessaging } from 'firebase-admin/messaging';
import { setGlobalOptions } from 'firebase-functions/v2';

if (getApps().length === 0) initializeApp();

// Região única e próxima do público-alvo. Cross-region em Callable custa ~80ms de RTT
// que nenhum minInstances recupera.
export const REGION = 'southamerica-east1';

setGlobalOptions({
  region: REGION,
  // Teto rígido em TODAS as functions. Sem isso, um loop de retry no cliente vira fatura.
  maxInstances: 20,
  // 2ª geração: N requests por instância. Compensa cold start sem pagar minInstances.
  concurrency: 80,
  memory: '512MiB',
  timeoutSeconds: 30,
});

export const db = getFirestore();
export const auth = getAuth();
/**
 * RTDB é LAZY de propósito. `getDatabase()` no carregamento do módulo lança
 * "Can't determine Firebase Database URL" em qualquer contexto sem databaseURL
 * configurado — testes unitários, scripts, emulador parcial. Efeito colateral no
 * import torna o módulo intestável; a função adia isso para o primeiro uso real.
 */
let _rtdb: ReturnType<typeof getDatabase> | null = null;
export const rtdb = () => (_rtdb ??= getDatabase());
export const messaging = getMessaging();
export { FieldValue, Timestamp };

db.settings({ ignoreUndefinedProperties: false });

export const SCHEMA_VERSION = 1;

export const isProd = process.env.SHIELDACK_ENV === 'prod';

// minInstances só no caminho mais sensível a p95, e só em prod. Ver docs/00-CORRECOES.md C9.
export const CRITICAL_PATH = isProd ? { minInstances: 1 } : {};

type Ref = FirebaseFirestore.DocumentReference;
type Snaps<T extends readonly unknown[]> = { [K in keyof T]: FirebaseFirestore.DocumentSnapshot };

/**
 * `getAll` tipado como TUPLA.
 *
 * O `getAll` do Admin SDK devolve `DocumentSnapshot[]`, o que sob
 * `noUncheckedIndexedAccess` torna todo destructuring `possibly undefined` e
 * enche o código de `!`. Estes dois wrappers preservam o aridade no tipo —
 * e um `!` a menos é um crash a menos em produção.
 */
export function getAll<T extends readonly Ref[]>(...refs: T): Promise<Snaps<T>> {
  return db.getAll(...refs) as Promise<Snaps<T>>;
}

export function txGetAll<T extends readonly Ref[]>(
  tx: FirebaseFirestore.Transaction,
  ...refs: T
): Promise<Snaps<T>> {
  return tx.getAll(...refs) as Promise<Snaps<T>>;
}
