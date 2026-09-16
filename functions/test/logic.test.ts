import { describe, it, expect } from 'vitest';
import { Timestamp } from 'firebase-admin/firestore';
import { isCorrect } from '../src/lib/grading';
import { currentHearts, nextRegenAt, MAX_HEARTS } from '../src/lib/hearts';
import { advanceStreak, civilDay } from '../src/lib/streak';
import { levelForXp, periodId } from '../src/lib/xp';
import { canTransition } from '../src/duel';

// Lógica pura, sem I/O. Se um destes quebrar, o produto está errado —
// não importa se as Rules e o deploy estão perfeitos.

describe('grading', () => {
  it('múltipla escolha exige igualdade de tipo e valor', () => {
    expect(isCorrect('single', 1, 1)).toBe(true);
    expect(isCorrect('single', '1', 1)).toBe(false); // string não passa por número
    expect(isCorrect('single', 0, 1)).toBe(false);
  });

  it('ordenação exige a sequência exata', () => {
    expect(isCorrect('order', [0, 1, 2], [0, 1, 2])).toBe(true);
    expect(isCorrect('order', [0, 2, 1], [0, 1, 2])).toBe(false);
    expect(isCorrect('order', [0, 1], [0, 1, 2])).toBe(false);
  });

  it('terminal normaliza espaço e caixa, mas NÃO flags', () => {
    expect(isCorrect('fill', '  NMAP -sV   host ', 'nmap -sV host')).toBe(true);
    expect(isCorrect('fill', 'rm -r /tmp', 'rm -rf /tmp')).toBe(false);
  });

  it('tipo desconhecido nunca é correto (fail closed)', () => {
    expect(isCorrect('nope' as never, 1, 1)).toBe(false);
  });
});

describe('hearts — regeneração por timestamp, não por timer', () => {
  const t0 = new Date('2026-09-15T12:00:00Z');
  const ts = (d: string) => Timestamp.fromDate(new Date(d));

  it('regenera 1 vida a cada 30 min', () => {
    expect(currentHearts(2, ts('2026-09-15T11:00:00Z'), t0)).toBe(4);
  });

  it('não passa do máximo', () => {
    expect(currentHearts(4, ts('2026-09-15T00:00:00Z'), t0)).toBe(MAX_HEARTS);
  });

  it('relógio do cliente adiantado não cria vidas: usamos SEMPRE o now do servidor', () => {
    // Um timestamp no futuro (possível se o servidor gravou adiantado) não regride vidas.
    expect(currentHearts(1, ts('2026-09-15T13:00:00Z'), t0)).toBe(1);
  });

  it('informa quando cai a próxima vida', () => {
    expect(nextRegenAt(1, ts('2026-09-15T11:50:00Z'), t0)?.toISOString())
      .toBe('2026-09-15T12:20:00.000Z');
    expect(nextRegenAt(MAX_HEARTS, ts('2026-09-15T11:50:00Z'), t0)).toBeNull();
  });
});

describe('streak — dia civil no fuso do usuário', () => {
  it('22h em São Paulo é o MESMO dia, não o dia UTC seguinte', () => {
    const at = new Date('2026-09-16T01:30:00Z'); // 22:30 de 15/09 em SP
    expect(civilDay(at, 'America/Sao_Paulo')).toBe('2026-09-15');
    expect(civilDay(at, 'UTC')).toBe('2026-09-16'); // o bug que evitamos
  });

  it('dia seguinte incrementa, dia repetido não, buraco reseta', () => {
    const tz = 'America/Sao_Paulo';
    const d15 = new Date('2026-09-15T15:00:00Z');
    const d16 = new Date('2026-09-16T15:00:00Z');
    const d18 = new Date('2026-09-18T15:00:00Z');

    const s1 = advanceStreak({ streakDays: 0, lastStudyDay: null }, d15, tz);
    expect(s1.streakDays).toBe(1);

    expect(advanceStreak(s1, d15, tz).streakDays).toBe(1); // mesmo dia, sem dupla contagem

    const s2 = advanceStreak(s1, d16, tz);
    expect(s2.streakDays).toBe(2);

    expect(advanceStreak(s2, d18, tz).streakDays).toBe(1); // pulou um dia
  });

  it('fuso inválido cai para UTC em vez de lançar', () => {
    expect(() => civilDay(new Date(), 'Marte/Olympus')).not.toThrow();
  });
});

describe('xp', () => {
  it('curva de nível é monotônica', () => {
    let prev = 0;
    for (const xp of [0, 99, 100, 282, 283, 5000]) {
      const l = levelForXp(xp);
      expect(l).toBeGreaterThanOrEqual(prev);
      prev = l;
    }
  });

  it('periodId é ISO week estável', () => {
    expect(periodId(new Date('2026-09-15T12:00:00Z'))).toMatch(/^2026-W\d{2}$/);
  });
});

describe('duel — máquina de estados', () => {
  it('permite apenas as transições legais', () => {
    expect(canTransition('pending', 'accepted')).toBe(true);
    expect(canTransition('accepted', 'in_progress')).toBe(true);
    expect(canTransition('in_progress', 'finished')).toBe(true);
    expect(canTransition('pending', 'expired')).toBe(true);
  });

  it('nega pular etapa e nega ressuscitar duelo terminal', () => {
    expect(canTransition('pending', 'finished')).toBe(false);
    expect(canTransition('finished', 'in_progress')).toBe(false);
    expect(canTransition('expired', 'accepted')).toBe(false);
  });
});
