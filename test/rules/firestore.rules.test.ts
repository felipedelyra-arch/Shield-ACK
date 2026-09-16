import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, serverTimestamp, collection, getDocs, query, where } from 'firebase/firestore';
import { beforeAll, afterAll, beforeEach, describe, expect, it } from 'vitest';
import { setupEnv, testEnv, asUser, asAnon, seed } from './setup';

const ALICE = 'aliceAAAAAAAAAAAAAAAAAAAAAAAA';
const BOB = 'bobBBBBBBBBBBBBBBBBBBBBBBBBBB';

beforeAll(async () => {
  await setupEnv();
  await seed(async (db) => {
    await db.doc(`users/${ALICE}`).set({ displayName: 'Alice', xp: 100, level: 3, hearts: 5, friendCode: 'ABCD2345' });
    await db.doc(`users/${BOB}`).set({ displayName: 'Bob', xp: 50, level: 2, hearts: 5, friendCode: 'WXYZ6789' });
    await db.doc(`users/${ALICE}/private/profile`).set({ email: 'alice@example.com' });
    await db.doc(`users/${ALICE}/progress/lesson1`).set({ status: 'completed' });
    await db.doc(`users/${ALICE}/xpEvents/evt1`).set({ amount: 20 });
    await db.doc('lessons/lesson1').set({ title: 'TLS 1.3', order: 0 });
    await db.doc('lessons/lesson1/questions/q1').set({ type: 'single', prompt: 'Qual porta?', options: ['22', '443'] });
    await db.doc('answerKeys/q1').set({ lessonId: 'lesson1', correct: 1, explanation: 'HTTPS usa 443.' });
    await db.doc('catalog/v1').set({ tracks: [] });
    await db.doc('friendships/' + [ALICE, BOB].sort().join('_')).set({ members: [ALICE, BOB] });
    await db.doc('duels/duel1').set({ players: [ALICE, BOB], state: 'pending', scores: {} });
    await db.doc('leaderboards/2026-W38/members/' + ALICE).set({ rank: 1, xp: 100 });
    await db.doc('auditLogs/log1').set({ action: 'x' });
    await db.doc('rateLimits/x__y').set({ count: 1 });
    await db.doc('counters/global/shards/0').set({ value: 1 });
    await db.doc('devices/tok1').set({ uid: ALICE, fcmToken: 't' });
  });
});

afterAll(() => testEnv.cleanup());

// ============================================================ GABARITO
// A rule mais importante do produto. Se este bloco passar a falhar, o app
// perde a razão de existir.
describe('answerKeys — o gabarito nunca trafega', () => {
  it('nega leitura a usuário autenticado', async () => {
    await assertFails(getDoc(doc(asUser(ALICE).firestore(), 'answerKeys/q1')));
  });

  it('nega leitura a admin autenticado', async () => {
    await assertFails(getDoc(doc(asUser(ALICE, { role: 'admin' }).firestore(), 'answerKeys/q1')));
  });

  it('nega escrita a qualquer um', async () => {
    await assertFails(setDoc(doc(asUser(ALICE, { role: 'admin' }).firestore(), 'answerKeys/q9'), { correct: 0 }));
  });

  it('a questão é legível e NÃO contém a resposta', async () => {
    const snap = await assertSucceeds(getDoc(doc(asUser(ALICE).firestore(), 'lessons/lesson1/questions/q1')));
    expect(Object.keys(snap.data()!)).not.toContain('correct');
  });
});

// ============================================================ PROGRESSO / XP
describe('progresso e XP — cliente não escreve', () => {
  it('dono LÊ o próprio progresso', async () => {
    await assertSucceeds(getDoc(doc(asUser(ALICE).firestore(), `users/${ALICE}/progress/lesson1`)));
  });

  it('terceiro NÃO lê progresso alheio', async () => {
    await assertFails(getDoc(doc(asUser(BOB).firestore(), `users/${ALICE}/progress/lesson1`)));
  });

  it('dono NÃO escreve o próprio progresso (só a Function escreve)', async () => {
    await assertFails(setDoc(doc(asUser(ALICE).firestore(), `users/${ALICE}/progress/lesson2`), { status: 'completed' }));
  });

  it('dono NÃO forja xpEvent', async () => {
    await assertFails(setDoc(doc(asUser(ALICE).firestore(), `users/${ALICE}/xpEvents/forged`), { amount: 999999 }));
  });

  it('dono NÃO altera o cache de xp em users/{uid}', async () => {
    await assertFails(updateDoc(doc(asUser(ALICE).firestore(), `users/${ALICE}`), { xp: 999999 }));
  });

  it('dono NÃO altera vidas', async () => {
    await assertFails(updateDoc(doc(asUser(ALICE).firestore(), `users/${ALICE}`), { hearts: 99 }));
  });

  it('dono NÃO altera streak', async () => {
    await assertFails(updateDoc(doc(asUser(ALICE).firestore(), `users/${ALICE}`), { streakDays: 365 }));
  });
});

// ============================================================ PERFIL
describe('perfil — whitelist de campos', () => {
  it('PERMITE editar displayName com updatedAt do servidor', async () => {
    await assertSucceeds(
      updateDoc(doc(asUser(ALICE).firestore(), `users/${ALICE}`), {
        displayName: 'Alice S.',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('NEGA displayName acima de 40 chars', async () => {
    await assertFails(
      updateDoc(doc(asUser(ALICE).firestore(), `users/${ALICE}`), {
        displayName: 'x'.repeat(41),
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('NEGA photoUrl que não seja https', async () => {
    await assertFails(
      updateDoc(doc(asUser(ALICE).firestore(), `users/${ALICE}`), {
        photoUrl: 'http://evil.tld/x.png',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('NEGA mass assignment (campo válido + campo proibido no mesmo write)', async () => {
    await assertFails(
      updateDoc(doc(asUser(ALICE).firestore(), `users/${ALICE}`), {
        displayName: 'Alice',
        xp: 999999,
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('NEGA updatedAt forjado pelo cliente', async () => {
    await assertFails(
      updateDoc(doc(asUser(ALICE).firestore(), `users/${ALICE}`), {
        displayName: 'Alice',
        updatedAt: new Date(2000, 0, 1),
      }),
    );
  });

  it('NEGA editar perfil alheio', async () => {
    await assertFails(
      updateDoc(doc(asUser(BOB).firestore(), `users/${ALICE}`), { displayName: 'hacked', updatedAt: serverTimestamp() }),
    );
  });

  it('NEGA criar e deletar o próprio users/{uid}', async () => {
    await assertFails(setDoc(doc(asUser('novoUsuarioAAAAAAAAAAAAAAAAAA').firestore(), 'users/novoUsuarioAAAAAAAAAAAAAAAAAA'), { xp: 0 }));
    await assertFails(deleteDoc(doc(asUser(ALICE).firestore(), `users/${ALICE}`)));
  });
});

// ============================================================ PRIVADO
describe('dados privados', () => {
  it('dono lê o próprio /private', async () => {
    await assertSucceeds(getDoc(doc(asUser(ALICE).firestore(), `users/${ALICE}/private/profile`)));
  });

  it('terceiro NÃO lê /private — e-mail nunca vaza', async () => {
    await assertFails(getDoc(doc(asUser(BOB).firestore(), `users/${ALICE}/private/profile`)));
  });

  it('dono NÃO escreve em /private', async () => {
    await assertFails(setDoc(doc(asUser(ALICE).firestore(), `users/${ALICE}/private/profile`), { email: 'x' }));
  });
});

// ============================================================ SOCIAL
describe('social exige e-mail verificado', () => {
  it('NEGA ler amizade sem e-mail verificado', async () => {
    const pair = [ALICE, BOB].sort().join('_');
    await assertFails(getDoc(doc(asUser(ALICE, { verified: false }).firestore(), `friendships/${pair}`)));
  });

  it('PERMITE ler a própria amizade com e-mail verificado', async () => {
    const pair = [ALICE, BOB].sort().join('_');
    await assertSucceeds(getDoc(doc(asUser(ALICE).firestore(), `friendships/${pair}`)));
  });

  it('NEGA criar amizade pelo cliente', async () => {
    await assertFails(setDoc(doc(asUser(ALICE).firestore(), 'friendships/forged'), { members: [ALICE, BOB] }));
  });

  it('NEGA ler duelo de que não participa', async () => {
    await assertFails(getDoc(doc(asUser('carolCCCCCCCCCCCCCCCCCCCCCCCC').firestore(), 'duels/duel1')));
  });

  it('NEGA escrever placar de duelo', async () => {
    await assertFails(updateDoc(doc(asUser(ALICE).firestore(), 'duels/duel1'), { scores: { [ALICE]: 9999 } }));
  });

  it('NEGA escrever no ranking', async () => {
    await assertFails(setDoc(doc(asUser(ALICE).firestore(), `leaderboards/2026-W38/members/${ALICE}`), { rank: 1, xp: 999999 }));
  });

  it('PERMITE ler o ranking', async () => {
    await assertSucceeds(getDoc(doc(asUser(ALICE).firestore(), `leaderboards/2026-W38/members/${ALICE}`)));
  });
});

// ============================================================ SERVER-ONLY
describe('coleções exclusivamente do servidor', () => {
  it.each(['auditLogs/log1', 'rateLimits/x__y', 'counters/global/shards/0'])(
    'nega leitura de %s',
    async (path) => {
      await assertFails(getDoc(doc(asUser(ALICE, { role: 'admin' }).firestore(), path)));
    },
  );

  it('nega escrita em auditLogs', async () => {
    await assertFails(setDoc(doc(asUser(ALICE).firestore(), 'auditLogs/forged'), { action: 'x' }));
  });

  it('nega escrita em devices (registerDevice é Callable)', async () => {
    await assertFails(setDoc(doc(asUser(ALICE).firestore(), 'devices/tok2'), { uid: ALICE, fcmToken: 't' }));
  });
});

// ============================================================ ANÔNIMO
describe('não autenticado', () => {
  it.each(['users/' + ALICE, 'lessons/lesson1', 'catalog/v1', 'answerKeys/q1'])(
    'nega leitura de %s',
    async (path) => {
      await assertFails(getDoc(doc(asAnon().firestore(), path)));
    },
  );
});

// ============================================================ CATCH-ALL
describe('default deny', () => {
  it('nega coleção não declarada nas rules', async () => {
    await assertFails(getDoc(doc(asUser(ALICE).firestore(), 'colecaoQueNaoExiste/doc1')));
    await assertFails(setDoc(doc(asUser(ALICE).firestore(), 'colecaoQueNaoExiste/doc1'), { a: 1 }));
  });
});
