import 'package:flutter_test/flutter_test.dart';
import 'package:shieldack/domain/entities/learning.dart';

LessonProgress _p({bool completed = false, int attempts = 0, int at = 0}) =>
    LessonProgress(
        completed: completed, attempts: attempts, lastPositionSec: at);

void main() {
  test('desbloqueio espelha o startLesson: 1ª livre, demais pedem a anterior',
      () {
    expect(
      resolveModule([_p(completed: true), _p(at: 30), null, null]),
      [
        LessonStatus.completed,
        LessonStatus.inProgress,
        LessonStatus.locked, // anterior só começada não libera
        LessonStatus.locked,
      ],
    );
    expect(resolveModule([null, null]),
        [LessonStatus.available, LessonStatus.locked]);
    expect(resolveModule([_p(completed: true), null]),
        [LessonStatus.completed, LessonStatus.available]);
  });

  test('tentativa sem conclusão é reprovação, não "em andamento"', () {
    expect(resolveModule([_p(attempts: 1, at: 600)]), [LessonStatus.failed]);
  });

  test('vidas regeneram 1 a cada 30 min, até 5', () {
    final t = DateTime(2026, 9, 17, 10);
    expect(displayHearts(2, t, t.add(const Duration(minutes: 29))), 2);
    expect(displayHearts(2, t, t.add(const Duration(minutes: 61))), 4);
    expect(displayHearts(2, t, t.add(const Duration(hours: 9))), 5);
    expect(displayHearts(2, t, t.subtract(const Duration(hours: 1))), 2,
        reason: 'relógio do aparelho atrasado não tira vida');
  });
}
