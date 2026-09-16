import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../demo/demo_state.dart';
import '../../../theme.dart';
import '../../../widgets/trace.dart';

/// Resultado do questionário.
///
/// Este é o ÚNICO momento animado do app. A sequência desenha o handshake
/// fechando — SYN, SYN-ACK, ACK — e só então revela o XP. É o momento que dá
/// nome ao produto, então é onde a atenção deve ir; todo o resto fica quieto.
///
/// Quando o aluno não passa, a mesma sequência termina em RST. A metáfora tem
/// que funcionar nos dois sentidos, senão vira enfeite.
class ResultPage extends StatefulWidget {
  const ResultPage({
    required this.correct,
    required this.total,
    required this.lesson,
    required this.demo,
    super.key,
  });

  final int correct;
  final int total;
  final DemoLesson lesson;
  final DemoState demo;

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  bool get _passed => widget.correct / widget.total >= 0.7;

  @override
  void initState() {
    super.initState();
    // Respeita quem desligou animação no sistema: sem movimento, vai direto ao fim.
    final reduce = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    reduce ? _c.value = 1 : _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final xpGained = _passed
        ? widget.lesson.xpReward +
            (widget.correct == widget.total ? (widget.lesson.xpReward * .25).round() : 0)
        : 0;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              SizedBox(
                height: 120,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) =>
                      CustomPaint(painter: _HandshakePainter(_c.value, _passed), size: Size.infinite),
                ),
              ),
              const SizedBox(height: Gap.xl),
              FadeTransition(
                opacity: CurvedAnimation(parent: _c, curve: const Interval(0.75, 1)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _passed ? 'Conexão estabelecida' : 'Conexão derrubada',
                      style: Face.display.copyWith(
                          color: _passed ? Wire.ack.color : Wire.rst.color),
                    ),
                    const SizedBox(height: Gap.sm),
                    Text(
                      _passed
                          ? '${widget.correct} de ${widget.total} corretas.'
                          : '${widget.correct} de ${widget.total} corretas. '
                              'Você precisa de ${(widget.total * 0.7).ceil()} para passar.',
                      style: Face.body.copyWith(color: Shade.textDim),
                    ),
                    const SizedBox(height: Gap.xl),
                    Row(
                      children: [
                        Field(
                          value: _passed ? '+$xpGained' : '0',
                          label: 'XP',
                          tone: _passed ? Wire.ack.color : Shade.textFaint,
                        ),
                        const SizedBox(width: Gap.xl),
                        Field(value: '${widget.demo.streak}', label: 'dias seguidos'),
                        const SizedBox(width: Gap.xl),
                        Field(
                          value: '${widget.demo.hearts}',
                          label: widget.demo.hearts == 1 ? 'vida' : 'vidas',
                          tone: widget.demo.hearts <= 1 ? Wire.rst.color : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Spacer(),
              ActionButton(
                _passed ? 'Continuar' : 'Tentar de novo',
                tone: _passed ? Wire.ack.color : Wire.syn.color,
                onPressed: () => _passed ? context.go('/') : context.pop(),
              ),
              if (!_passed) ...[
                const SizedBox(height: Gap.sm),
                Center(
                  child: TextButton(
                    onPressed: () => context.go('/'),
                    child: Text('Voltar para a trilha',
                        style: Face.meta.copyWith(color: Shade.textDim)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Desenha o handshake em três tempos: SYN sobe, SYN-ACK volta, ACK fecha.
/// No caso de reprovação, o terceiro tempo vira um RST.
class _HandshakePainter extends CustomPainter {
  _HandshakePainter(this.t, this.passed);
  final double t;
  final bool passed;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 14.0;
    final right = size.width - 14;
    const rowH = 34.0;

    final rail = Paint()
      ..color = Shade.rule
      ..strokeWidth = 1;
    canvas
      ..drawLine(const Offset(left, 0), Offset(left, size.height), rail)
      ..drawLine(Offset(right, 0), Offset(right, size.height), rail);

    final steps = [
      (y: rowH * 0.5, from: left, to: right, label: 'SYN', tone: Wire.syn.color),
      (y: rowH * 1.5, from: right, to: left, label: 'SYN-ACK', tone: Wire.syn.color),
      (
        y: rowH * 2.5,
        from: left,
        to: right,
        label: passed ? 'ACK' : 'RST',
        tone: passed ? Wire.ack.color : Wire.rst.color,
      ),
    ];

    for (var i = 0; i < steps.length; i++) {
      final s = steps[i];
      // Cada passo ocupa um terço do tempo, na ordem — é um handshake, não um fade.
      final local = ((t - i / 3) * 3).clamp(0.0, 1.0);
      if (local == 0) continue;

      final x = s.from + (s.to - s.from) * Curves.easeOutCubic.transform(local);
      final paint = Paint()
        ..color = s.tone
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(Offset(s.from, s.y), Offset(x, s.y), paint);

      if (local > 0.15) {
        final tp = TextPainter(
          text: TextSpan(
            text: s.label,
            style: Face.code.copyWith(fontSize: 11, color: s.tone),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset((left + right) / 2 - tp.width / 2, s.y - tp.height - 4));
      }

      if (local == 1) {
        canvas.drawCircle(Offset(s.to, s.y), 3.5, Paint()..color = s.tone);
      }
    }
  }

  @override
  bool shouldRepaint(_HandshakePainter old) => old.t != t || old.passed != passed;
}
