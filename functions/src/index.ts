/**
 * Superfície pública das Cloud Functions.
 * Nenhuma função é exportada sem passar pelo wrapper `guarded()`
 * (App Check → auth → claims → schema zod → rate limit).
 * Exceções: triggers de Identity e funções agendadas, que não recebem entrada do cliente.
 */
export { startLesson } from './startLesson';
export { getLessonPlayback } from './getLessonPlayback';
export { submitQuiz } from './submitQuiz';
export { syncWatchProgress } from './syncWatchProgress';
export { createDuel, respondDuel, submitDuelRound } from './duel';
export { sendFriendRequest, respondFriendRequest, updateUsername } from './friends';
export { registerDevice } from './devices';
export { requestAccountDeletion, processDeletion, exportMyData } from './lgpd';
export { publishCatalog, setUserRole } from './admin/publishCatalog';
export { beforeCreate, beforeSignIn, bootstrapProfile } from './triggers/onUserCreate';
export { buildLeaderboard, expireDuels, reconcileXp, inactivityPush } from './scheduled';
