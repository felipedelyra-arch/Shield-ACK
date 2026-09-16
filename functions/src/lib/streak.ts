/**
 * Streak no fuso do usuário. O bug clássico aqui é comparar datas em UTC:
 * um usuário em São Paulo que estuda às 22h tem o dia UTC seguinte, e a streak
 * "pula" ou quebra sem motivo. Comparamos o DIA CIVIL no tz do usuário.
 */
export function civilDay(at: Date, tz: string): string {
  try {
    return new Intl.DateTimeFormat('en-CA', {
      timeZone: tz,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).format(at);
  } catch {
    return new Intl.DateTimeFormat('en-CA', { timeZone: 'UTC' }).format(at);
  }
}

export function isValidTimeZone(tz: string): boolean {
  try {
    new Intl.DateTimeFormat('en', { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

export interface StreakState {
  streakDays: number;
  lastStudyDay: string | null;
}

export function advanceStreak(prev: StreakState, now: Date, tz: string): StreakState {
  const today = civilDay(now, tz);
  if (prev.lastStudyDay === today) return prev; // já contou hoje

  const yesterday = civilDay(new Date(now.getTime() - 86400000), tz);
  const streakDays = prev.lastStudyDay === yesterday ? prev.streakDays + 1 : 1;
  return { streakDays, lastStudyDay: today };
}
