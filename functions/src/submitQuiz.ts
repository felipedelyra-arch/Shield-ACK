import { db, FieldValue, Timestamp, SCHEMA_VERSION, CRITICAL_PATH, getAll, txGetAll } from './lib/init';
import { guarded } from './lib/guard';
import { submitQuizInput } from './domain/schemas';
import { Err } from './lib/errors';
import { audit } from './lib/audit';
import { stageXp } from './lib/xp';
import { isCorrect, QuestionType } from './lib/grading';
import { advanceStreak } from './lib/streak';
import { currentHearts, MAX_HEARTS } from './lib/hearts';

const PASS_THRESHOLD = 0.7;

/** Piso de tempo plausível por questão. Abaixo disso é bot ou replay, não leitura. */
const MIN_MS_PER_QUESTION = 1200;

export const submitQuiz = guarded(
  {
    action: 'submitQuiz',
    schema: submitQuizInput,
    limit: { max: 30, windowSec: 300 },
    options: CRITICAL_PATH,
  },
  async (data, ctx) => {
    const { lessonId, answers, idempotencyKey, clientElapsedMs } = data;

    // --- 1. Replay: o ledger é a trava. Se já existe evento com esta chave,
    // devolvemos o resultado gravado em vez de recorrigir e reemitir XP.
    const ackRef = db.collection('users').doc(ctx.uid).collection('outboxAck').doc(idempotencyKey);
    const ack = await ackRef.get();
    if (ack.exists) return { ...ack.data()!.result, replayed: true };

    // --- 2. Autorização de sequência: quem decide se a lição pode ser respondida é
    // o servidor, não a UI. O cliente desenha a trilha; aqui ela é validada.
    const lessonRef = db.collection('lessons').doc(lessonId); // lessonId já validado por regex
    const progressRef = db.collection('users').doc(ctx.uid).collection('progress').doc(lessonId);
    const userRef = db.collection('users').doc(ctx.uid);

    const [lessonSnap, progressSnap, userSnap] = await getAll(lessonRef, progressRef, userRef);
    if (!lessonSnap.exists) throw Err.notFound();
    if (!progressSnap.exists || progressSnap.get('status') === 'locked') {
      await audit('quiz_on_locked_lesson', ctx.uid, 'warn', { lessonId });
      throw Err.locked('LESSON_LOCKED');
    }

    // --- 3. Vidas: derivadas de timestamp do servidor, nunca de timer do cliente.
    const hearts = currentHearts(
      userSnap.get('hearts') ?? MAX_HEARTS,
      userSnap.get('heartsUpdatedAt') ?? null,
      new Date(),
    );
    if (hearts <= 0) throw Err.locked('NO_HEARTS');

    // --- 4. Anti-cheat de tempo. clientElapsedMs é sinal, não verdade — por isso
    // ele só ALIMENTA a auditoria e um bloqueio grosseiro, nunca a nota.
    const floorMs = answers.length * MIN_MS_PER_QUESTION;
    const suspiciouslyFast = clientElapsedMs < floorMs;
    if (suspiciouslyFast) {
      await audit('quiz_too_fast', ctx.uid, 'warn', {
        lessonId,
        clientElapsedMs,
        floorMs,
        questions: answers.length,
      });
    }

    // --- 5. Correção contra answerKeys. Esta coleção é inacessível por Rules;
    // só o Admin SDK chega aqui. O gabarito nunca sai desta função.
    const questionIds = answers.map((a) => a.questionId);
    if (new Set(questionIds).size !== questionIds.length) throw Err.invalidArg('DUPLICATE_QUESTION');

    // Todas as questões da lição, não só as enviadas: a nota é acertos ÷ respondidas,
    // então responder só a que se sabe daria 100%.
    const lessonQuestions = await lessonRef.collection('questions').limit(20).get();
    const qById = new Map(lessonQuestions.docs.map((d) => [d.id, d]));
    if (qById.size !== questionIds.length || !questionIds.every((id) => qById.has(id))) {
      throw Err.invalidArg('INCOMPLETE_ANSWERS');
    }

    const keySnaps = await db.getAll(...questionIds.map((qid) => db.collection('answerKeys').doc(qid)));

    const perQuestion = answers.map((a, i) => {
      const key = keySnaps[i];
      const q = qById.get(a.questionId)!;
      // Gabarito de outra lição não vale — impede montar um quiz com questões fáceis.
      if (!key?.exists || key.get('lessonId') !== lessonId) {
        return { questionId: a.questionId, correct: false, explanation: '' };
      }
      const type = q.get('type') as QuestionType;
      return {
        questionId: a.questionId,
        correct: isCorrect(type, a.value, key.get('correct')),
        explanation: (key.get('explanation') as string) ?? '',
      };
    });

    const correctCount = perQuestion.filter((p) => p.correct).length;
    const score = correctCount / answers.length;
    const passed = score >= PASS_THRESHOLD && !suspiciouslyFast;

    // --- 6. Efeitos, numa transação só. O ack é relido AQUI: é ele que trava a chave.
    // O check do passo 1 é só atalho. Sem isto, N retries simultâneos passariam todos
    // por ele e cada um gravaria tentativa, streak e — se reprovado — tiraria uma vida.
    const baseXp = (lessonSnap.get('xpReward') as number) ?? 20;
    const xpAmount = passed ? Math.round(baseXp * (score === 1 ? 1.25 : 1)) : 0;
    const eventRef = userRef.collection('xpEvents').doc(idempotencyKey);

    return db.runTransaction(async (tx) => {
      const [ackTx, progressTx, userTx, eventTx] = await txGetAll(tx, ackRef, progressRef, userRef, eventRef);
      if (ackTx.exists) return { ...ackTx.data()!.result, replayed: true };

      // Relido na transação: outra chave pode ter consumido vidas desde o passo 3.
      const now = new Date();
      const heartsNow = currentHearts(userTx.get('hearts') ?? MAX_HEARTS, userTx.get('heartsUpdatedAt') ?? null, now);
      if (heartsNow <= 0) throw Err.locked('NO_HEARTS');
      const heartsAfter = passed ? heartsNow : heartsNow - 1;

      const xp = passed
        ? stageXp(
            tx,
            { uid: ctx.uid, eventId: idempotencyKey, amount: xpAmount, reason: score === 1 ? 'quiz_perfect' : 'lesson_complete', ref: `lessons/${lessonId}` },
            userTx.get('xp') ?? 0,
            eventTx.exists,
          )
        : { awarded: 0, totalXp: userTx.get('xp') ?? 0, level: userTx.get('level') ?? 1 };

      const tz = (userTx.get('tz') as string) ?? 'America/Sao_Paulo';
      const streak = advanceStreak(
        { streakDays: userTx.get('streakDays') ?? 0, lastStudyDay: userTx.get('lastStudyDay') ?? null },
        now,
        tz,
      );

      // Progresso é MONOTÔNICO: nunca regride de completed para in_progress,
      // e bestScore só sobe. É isto que torna dois dispositivos convergentes.
      const prevStatus = progressTx.get('status') as string;
      tx.set(
        progressRef,
        {
          status: passed || prevStatus === 'completed' ? 'completed' : 'in_progress',
          bestScore: Math.max((progressTx.get('bestScore') as number) ?? 0, score),
          completedAt: passed && prevStatus !== 'completed' ? FieldValue.serverTimestamp()
                                                            : progressTx.get('completedAt') ?? null,
          attempts: FieldValue.increment(1),
          updatedAt: FieldValue.serverTimestamp(),
          schemaVersion: SCHEMA_VERSION,
        },
        { merge: true },
      );

      tx.set(
        userRef,
        {
          streakDays: streak.streakDays,
          lastStudyDay: streak.lastStudyDay,
          hearts: heartsAfter,
          heartsUpdatedAt: Timestamp.fromDate(now),
          lastActiveAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      tx.create(userRef.collection('attempts').doc(), {
        lessonId,
        score,
        correctCount,
        total: answers.length,
        clientElapsedMs,
        flaggedFast: suspiciouslyFast,
        createdAt: FieldValue.serverTimestamp(),
        schemaVersion: SCHEMA_VERSION,
      });

      const result = {
        passed,
        score,
        correctCount,
        total: answers.length,
        xpAwarded: xp.awarded,
        totalXp: xp.totalXp,
        level: xp.level,
        hearts: heartsAfter,
        streakDays: streak.streakDays,
        perQuestion, // enunciado + acerto + explicação. Nunca a resposta das que errou.
        replayed: false,
      };

      // Ack idempotente: se a rede cair depois do commit, o retry do outbox devolve
      // exatamente este objeto em vez de reprocessar. TTL 7 dias.
      tx.create(ackRef, {
        result,
        createdAt: FieldValue.serverTimestamp(),
        expireAt: Timestamp.fromMillis(now.getTime() + 7 * 86400 * 1000),
      });

      return result;
    });
  },
);
