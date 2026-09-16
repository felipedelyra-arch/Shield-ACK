import {
  initializeTestEnvironment,
  RulesTestEnvironment,
  RulesTestContext,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

export let testEnv: RulesTestEnvironment;

export async function setupEnv(): Promise<RulesTestEnvironment> {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-shieldack',
    firestore: {
      rules: readFileSync(resolve(__dirname, '../../firestore.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
  return testEnv;
}

export function asUser(uid: string, opts: { verified?: boolean; role?: string } = {}): RulesTestContext {
  return testEnv.authenticatedContext(uid, {
    email_verified: opts.verified ?? true,
    role: opts.role ?? 'student',
  });
}

export const asAnon = () => testEnv.unauthenticatedContext();

/** Semeia dados ignorando as rules — é assim que se monta o estado do teste. */
export async function seed(fn: (db: FirebaseFirestore.Firestore) => Promise<void>) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await fn(ctx.firestore() as never);
  });
}
