import { onSchedule } from 'firebase-functions/v2/scheduler';
import { db, rtdb, messaging, FieldValue, Timestamp, REGION } from '../lib/init';
import { periodId, levelForXp } from '../lib/xp';
import { audit } from '../lib/audit';
import { civilDay } from '../lib/streak';

const TZ = 'America/Sao_Paulo';

// ---------------------------------------------------------------- ranking

/**
 * Materializa o ranking. Firestore não tem ORDER BY SUM() — ranking ao vivo é
 * impossível. Esta function agrega e grava já ORDENADO e PAGINÁVEL.
 *
 * Escala: até ~50k usuários isto cabe em memória. Acima disso, a agregação migra
 * para BigQuery (xpEvents já é exportado por streaming) e esta function apenas
 * importa o resultado. O ponto de virada está documentado em docs/06-operacao.md.
 */
export const buildLeaderboard = onSchedule(
  { schedule: 'every 15 minutes', timeZone: TZ, region: REGION, memory: '1GiB', timeoutSeconds: 540 },
  async () => {
    const period = periodId();
    const since = Timestamp.fromMillis(Date.now() - 8 * 86400 * 1000);

    // collectionGroup + paginação por cursor. Nunca uma query sem limit().
    const totals = new Map<string, number>();
    let cursor: FirebaseFirestore.QueryDocumentSnapshot | undefined;

    for (;;) {
      let q = db
        .collectionGroup('xpEvents')
        .where('periodId', '==', period)
        .where('createdAt', '>=', since)
        .orderBy('createdAt')
        .limit(2000);
      if (cursor) q = q.startAfter(cursor);

      const snap = await q.get();
      if (snap.empty) break;

      for (const d of snap.docs) {
        const uid = d.ref.parent.parent!.id;
        totals.set(uid, (totals.get(uid) ?? 0) + (d.get('amount') as number));
      }
      cursor = snap.docs[snap.docs.length - 1];
      if (snap.size < 2000) break;
    }

    const ranked = [...totals].sort((a, b) => b[1] - a[1]).slice(0, 5000);

    // BulkWriter: lida com throttling e retry automaticamente e não tem o teto
    // rígido de 500 operações do WriteBatch.
    const writer = db.bulkWriter();
    const col = db.collection('leaderboards').doc(period).collection('members');

    for (let i = 0; i < ranked.length; i++) {
      const [uid, xp] = ranked[i]!;
      const profile = await db.collection('users').doc(uid).get();
      void writer.set(col.doc(uid), {
        rank: i + 1,
        xp,
        level: levelForXp(profile.get('xp') ?? 0),
        displayName: profile.get('displayName') ?? '',
        photoUrl: profile.get('photoUrl') ?? null,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    await writer.close();
    await audit('leaderboard_built', null, 'info', { period, members: ranked.length });
  },
);

// ------------------------------------------------------------ expirar duelos

export const expireDuels = onSchedule(
  { schedule: 'every 10 minutes', timeZone: TZ, region: REGION },
  async () => {
    const now = Timestamp.now();
    const snap = await db
      .collection('duels')
      .where('state', 'in', ['pending', 'accepted', 'in_progress'])
      .where('expiresAt', '<=', now)
      .limit(400)
      .get();

    const writer = db.bulkWriter();
    for (const d of snap.docs) {
      void writer.update(d.ref, { state: 'expired', updatedAt: FieldValue.serverTimestamp() });
      void rtdb().ref(`duels/${d.id}`).remove();
      void rtdb().ref(`duelMembers/${d.id}`).remove();
    }
    await writer.close();

    if (snap.size > 0) await audit('duels_expired', null, 'info', { count: snap.size });
  },
);

// ------------------------------------------------- reconciliação do ledger

/**
 * users/{uid}.xp é CACHE. O ledger é a verdade. Esta function prova isso
 * continuamente: divergência vira auditoria e correção, não silêncio.
 */
export const reconcileXp = onSchedule(
  { schedule: '0 4 * * *', timeZone: TZ, region: REGION, timeoutSeconds: 540 },
  async () => {
    let cursor: FirebaseFirestore.QueryDocumentSnapshot | undefined;
    let fixed = 0;

    for (;;) {
      let q = db.collection('users').orderBy('__name__').limit(300);
      if (cursor) q = q.startAfter(cursor);
      const users = await q.get();
      if (users.empty) break;

      for (const u of users.docs) {
        const agg = await u.ref.collection('xpEvents').aggregate({ total: { sum: 'amount' } } as never).get();
        const truth = (agg.data() as { total: number }).total ?? 0;
        const cached = (u.get('xp') as number) ?? 0;
        if (truth !== cached) {
          await u.ref.update({ xp: truth, level: levelForXp(truth), updatedAt: FieldValue.serverTimestamp() });
          await audit('xp_divergence_fixed', u.id, 'critical', { cached, truth });
          fixed++;
        }
      }
      cursor = users.docs[users.docs.length - 1];
    }
    if (fixed > 0) await audit('xp_reconcile_done', null, 'warn', { fixed });
  },
);

// ----------------------------------------------------------- notificações

const MAX_PUSH_PER_DAY = 3;

/**
 * Push de inatividade. Paginado por índice em (notifyInactivity, lastActiveAt) —
 * jamais varrer a coleção inteira: com 100k usuários isso seriam 100k reads por tick.
 */
export const inactivityPush = onSchedule(
  { schedule: '0 19 * * *', timeZone: TZ, region: REGION, timeoutSeconds: 540 },
  async () => {
    const buckets = [
      { hours: 24, body: 'Sua sequência está em risco. 5 minutos salvam o streak.' },
      { hours: 72, body: 'Faz 3 dias. Bora terminar o módulo de Redes?' },
      { hours: 168, body: 'Seu progresso está te esperando.' },
    ];

    for (const bucket of buckets) {
      const from = Timestamp.fromMillis(Date.now() - (bucket.hours + 24) * 3600 * 1000);
      const to = Timestamp.fromMillis(Date.now() - bucket.hours * 3600 * 1000);

      let cursor: FirebaseFirestore.QueryDocumentSnapshot | undefined;
      for (;;) {
        let q = db
          .collection('users')
          .where('notifyInactivity', '==', true)
          .where('lastActiveAt', '>=', from)
          .where('lastActiveAt', '<', to)
          .limit(200);
        if (cursor) q = q.startAfter(cursor);

        const snap = await q.get();
        if (snap.empty) break;

        await Promise.allSettled(snap.docs.map((u) => sendToUser(u.id, 'inactivity', bucket.body)));
        cursor = snap.docs[snap.docs.length - 1];
        if (snap.size < 200) break;
      }
    }
  },
);

/**
 * Envio com teto diário, janela de silêncio no fuso do usuário, dedupe por
 * collapse_key e limpeza de token inválido. Rivalidade saudável != spam.
 * O payload NUNCA carrega PII — só um tipo e um deeplink.
 */
export async function sendToUser(uid: string, type: string, body: string): Promise<void> {
  const [userSnap, prefsSnap, devicesSnap] = await Promise.all([
    db.collection('users').doc(uid).get(),
    db.collection('users').doc(uid).collection('private').doc('profile').get(),
    db.collection('devices').where('uid', '==', uid).limit(5).get(),
  ]);

  if (devicesSnap.empty) return;
  if (prefsSnap.get(`notifPrefs.${type}`) === false) return;

  const tz = (userSnap.get('tz') as string) ?? TZ;
  const hour = Number(new Intl.DateTimeFormat('en', { timeZone: tz, hour: 'numeric', hour12: false }).format(new Date()));
  const quiet = (prefsSnap.get('quietHours') as { start: number; end: number }) ?? { start: 22, end: 8 };
  const inQuiet = quiet.start > quiet.end ? hour >= quiet.start || hour < quiet.end : hour >= quiet.start && hour < quiet.end;
  if (inQuiet) return;

  const today = civilDay(new Date(), tz);
  const capRef = db.collection('rateLimits').doc(`${uid}__push_${today}`);
  const sentToday = await db.runTransaction(async (tx) => {
    const s = await tx.get(capRef);
    const n = (s.get('count') as number) ?? 0;
    if (n >= MAX_PUSH_PER_DAY) return n;
    tx.set(capRef, { count: n + 1, expireAt: Timestamp.fromMillis(Date.now() + 2 * 86400 * 1000) }, { merge: true });
    return n;
  });
  if (sentToday >= MAX_PUSH_PER_DAY) return;

  const tokens = devicesSnap.docs.map((d) => d.get('fcmToken') as string);
  const res = await messaging.sendEachForMulticast({
    tokens,
    notification: { title: 'Shield Ack', body },
    data: { type, deeplink: `shieldack://home` }, // sem PII, sem conteúdo sensível
    android: { collapseKey: type, priority: 'normal' },
    apns: { headers: { 'apns-collapse-id': type } },
  });

  // Limpeza de token inválido no retorno do envio — sem isso a coleção enche de
  // tokens mortos e cada push custa uma chamada a mais, para sempre.
  const stale = res.responses
    .map((r, i) => (!r.success && ['messaging/registration-token-not-registered', 'messaging/invalid-argument'].includes(r.error?.code ?? '') ? devicesSnap.docs[i] : null))
    .filter((d): d is FirebaseFirestore.QueryDocumentSnapshot => d !== null);

  await Promise.all(stale.map((d) => d.ref.delete()));
}
