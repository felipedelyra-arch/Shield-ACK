/** Comparação de resposta por tipo. Pura, testável, sem I/O. */
export type QuestionType = 'single' | 'boolean' | 'order' | 'match' | 'fill';

export function isCorrect(type: QuestionType, given: unknown, expected: unknown): boolean {
  switch (type) {
    case 'single':
      return typeof given === 'number' && given === expected;

    case 'boolean':
      return typeof given === 'boolean' && given === expected;

    case 'order':
    case 'match':
      return (
        Array.isArray(given) &&
        Array.isArray(expected) &&
        given.length === expected.length &&
        given.every((v, i) => v === expected[i])
      );

    case 'fill': {
      // Comandos de terminal: normaliza espaços e caixa, mas NÃO ignora caracteres
      // significativos (`-rf`, `|`, `>`), porque a diferença entre eles é o conteúdo da aula.
      if (typeof given !== 'string' || typeof expected !== 'string') return false;
      const norm = (s: string) => s.trim().replace(/\s+/g, ' ').toLowerCase();
      return norm(given) === norm(expected);
    }

    default:
      return false;
  }
}
