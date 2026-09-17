/**
 * Popula o EMULADOR com o conteúdo da demo e publica `catalog/v1`
 * (o default de `catalog_version` no Remote Config do app).
 *
 * Uso, com `firebase emulators:start` rodando:
 *   npm --prefix functions run seed
 *
 * Recusa rodar sem FIRESTORE_EMULATOR_HOST: este script escreve gabarito.
 */
if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error('FIRESTORE_EMULATOR_HOST ausente — o seed só roda contra o emulador.');
  process.exit(1);
}
process.env.GCLOUD_PROJECT ??= 'demo-shieldack';

const { db } = require('../lib/lib/init');
const { buildCatalog } = require('../lib/admin/publishCatalog');

const QUESTIONS = [
  {
    type: 'single',
    prompt: 'O cliente acabou de enviar este segmento. O que o servidor responde?',
    code: 'Flags [S], seq 3829471028, win 64240\n  options [mss 1460,sackOK,TS]',
    options: ['SYN', 'SYN-ACK', 'ACK', 'RST'],
    correct: 1,
    explanation:
      'O servidor confirma o SYN recebido e envia o próprio SYN na mesma resposta — daí o nome ' +
      'SYN-ACK. O handshake fecha quando o cliente devolve o ACK final.',
  },
  {
    type: 'single',
    prompt: 'Uma porta responde com RST imediatamente. O que isso indica?',
    options: [
      'A porta está aberta e aceitando conexões',
      'Há um firewall descartando o pacote em silêncio',
      'A porta está fechada, mas o host está vivo',
      'O host está fora do ar',
    ],
    correct: 2,
    explanation:
      'RST é uma recusa ativa: alguém está lá para responder. Firewall que dropa não responde ' +
      'nada — é o timeout que denuncia filtragem, não o RST.',
  },
  {
    type: 'boolean',
    prompt: 'SHA-256 é uma boa escolha para armazenar senha de usuário.',
    options: ['Verdadeiro', 'Falso'],
    correct: false,
    explanation:
      'SHA-256 é rápido de propósito, e velocidade é exatamente o que o atacante quer num ataque ' +
      'de dicionário. Senha pede função lenta e com custo ajustável (Argon2id, bcrypt, scrypt).',
  },
];

const TRACKS = [
  ['redes', 'Redes', 'Do quadro Ethernet ao handshake TCP.', [
    ['modelo-osi', 'Modelo OSI na prática', 504, 40],
    ['handshake-tcp', 'Handshake TCP: SYN, SYN-ACK, ACK', 662, 40],
    ['portas-sockets', 'Portas, sockets e serviços', 738, 40],
    ['subredes-cidr', 'Subredes e CIDR', 810, 50],
    ['nat', 'NAT e port forwarding', 595, 50],
  ]],
  ['fundamentos', 'Fundamentos de segurança', 'Superfície de ataque e como reduzi-la.', [
    ['triade-cia', 'Tríade CIA sem decoreba', 420, 30],
    ['authn-authz', 'Autenticação vs autorização', 505, 40],
    ['hash-senha', 'Hashing: por que não SHA-256 em senha', 690, 50],
    ['tls13', 'TLS 1.3 e o que o cadeado não diz', 880, 50],
  ]],
  ['devsecops', 'DevSecOps', 'Segurança que roda no pipeline, não na reunião.', [
    ['segredos', 'Segredos fora do repositório', 460, 40],
    ['sast-dast-sca', 'SAST, DAST e SCA: quando cada um', 720, 50],
    ['proveniencia', 'Assinatura e proveniência de build', 640, 50],
  ]],
];

async function main() {
  const batch = db.batch();
  const meta = { schemaVersion: 1, createdAt: new Date(), updatedAt: new Date() };

  TRACKS.forEach(([trackId, title, blurb, lessons], trackOrder) => {
    const moduleId = `${trackId}-m1`;
    batch.set(db.doc(`tracks/${trackId}`), { title, blurb, level: 1, order: trackOrder, ...meta });
    batch.set(db.doc(`tracks/${trackId}/modules/${moduleId}`), {
      title, order: 0, lessonIds: lessons.map(([id]) => id), ...meta,
    });

    lessons.forEach(([lessonId, lessonTitle, durationSec, xpReward], order) => {
      batch.set(db.doc(`lessons/${lessonId}`), {
        trackId, moduleId, order, title: lessonTitle, durationSec, xpReward,
        videoAssetId: `dev-${lessonId}`, ...meta,
      });
      QUESTIONS.forEach(({ correct, explanation, ...question }, i) => {
        const qId = `${lessonId}-q${i}`;
        batch.set(db.doc(`lessons/${lessonId}/questions/${qId}`), { ...question, order: i, ...meta });
        batch.set(db.doc(`answerKeys/${qId}`), { lessonId, correct, explanation, ...meta });
      });
    });
  });

  await batch.commit();

  const { tracks, leaks } = await buildCatalog();
  if (leaks.length) throw new Error(`gabarito vazando em questões: ${leaks.join(', ')}`);
  await db.doc('catalog/v1').set({ tracks, publishedBy: 'seed', ...meta });

  console.log(`seed ok: ${tracks.length} trilhas em catalog/v1`);
}

main().then(() => process.exit(0), (e) => { console.error(e); process.exit(1); });
