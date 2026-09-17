import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/entities/learning.dart';
import '../../../../domain/entities/quiz_submission.dart';
import '../../../theme.dart';
import '../../../widgets/trace.dart';

/// Resultado do questionário, como o servidor corrigiu.
///
/// Este é o ÚNICO momento animado do app. A sequência desenha o handshake
/// fechando — SYN, SYN-ACK, ACK — e só então revela o XP. É o momento que dá
/// nome ao produto, então é onde a atenção deve ir; todo o resto fica quieto.
///
/// Quando o aluno não passa, a mesma sequência termina em RST. A metáfora tem
/// que funcionar nos dois sentidos, senão vira enfeite.
class ResultPage extends StatefulWidget {
  const ResultPage({
    required this.lesson,
    required this.questions,
    required this.outcome,
    super.key,
  });

  final Lesson lesson;
  final List<Question> questions;
  final QuizOutcome outcome;

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  /// Fração do tempo em que o ACK chega; depois dela vem a rajada.
  static const _ackAt = 0.6;

  @override
  void initState() {
    super.initState();
    // Respeita quem desligou animação no sistema: sem movimento, vai direto ao fim.
    final reduce = WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    reduce ? _c.value = 1 : _c.forward();
    // O toque no dedo chega junto com o ACK (ou o RST).
    var felt = false;
    _c.addListener(() {
      if (felt || _c.value < _ackAt) return;
      felt = true;
      widget.outcome.passed
          ? HapticFeedback.mediumImpact()
          : HapticFeedback.heavyImpact();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.outcome;
    if (o.pending) return const _Pending();

    final passed = o.passed;
    final needed = (o.total * 0.7).ceil();
    final prompts = {for (final q in widget.questions) q.id: q.prompt};

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(Gap.md),
                children: [
                  const SizedBox(height: Gap.xl),
                  SizedBox(
                    height: 120,
                    child: AnimatedBuilder(
                      animation: _c,
                      builder: (context, _) => CustomPaint(
                          painter: _HandshakePainter(_c.value, passed, _ackAt),
                          size: Size.infinite),
                    ),
                  ),
                  const SizedBox(height: Gap.xl),
                  FadeTransition(
                    opacity: CurvedAnimation(
                        parent: _c, curve: const Interval(0.5, 0.8)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          passed ? 'Conexão estabelecida' : 'Conexão derrubada',
                          style: Face.display.copyWith(
                              color: passed ? Wire.ack.color : Wire.rst.color),
                        ),
                        const SizedBox(height: Gap.sm),
                        Text(
                          switch (o) {
                            QuizOutcome(passed: true) =>
                              '${o.correctCount} de ${o.total} corretas.',
                            // Nota suficiente e mesmo assim reprovado: o piso de tempo do servidor.
                            _ when o.correctCount >= needed =>
                              'Respostas rápidas demais para contar. Refaça lendo com calma.',
                            _ =>
                              '${o.correctCount} de ${o.total} corretas. Você precisa de $needed para passar.',
                          },
                          style: Face.body.copyWith(color: Shade.textDim),
                        ),
                        const SizedBox(height: Gap.xl),
                        Row(
                          children: [
                            AnimatedBuilder(
                              animation: _c,
                              builder: (_, __) => Field(
                                // Conta junto com a rajada, termina no valor real.
                                value: passed
                                    ? '+${(o.xpAwarded * Curves.easeOut.transform(((_c.value - _ackAt) / (1 - _ackAt)).clamp(0.0, 1.0))).round()}'
                                    : '0',
                                label: 'XP',
                                tone: passed ? Wire.ack.color : Shade.textFaint,
                              ),
                            ),
                            const SizedBox(width: Gap.xl),
                            Field(
                              value: '${o.streakDays}',
                              label: o.streakDays == 1
                                  ? 'dia seguido'
                                  : 'dias seguidos',
                              tone: Wire.syn.color,
                            ),
                            const SizedBox(width: Gap.xl),
                            Field(
                              value: '${o.hearts}',
                              label: o.hearts == 1 ? 'vida' : 'vidas',
                              tone: o.hearts <= 1 ? Wire.rst.color : null,
                            ),
                          ],
                        ),
                        if (passed) ...[
                          const SizedBox(height: Gap.lg),
                          _LevelUp(
                              before: o.totalXp - o.xpAwarded,
                              after: o.totalXp),
                        ],
                        const SizedBox(height: Gap.xl),
                        // Explicação em todas, inclusive nos acertos: acertar por sorte
                        // e seguir adiante é pior do que errar.
                        for (final f in o.perQuestion) ...[
                          Text(prompts[f.questionId] ?? '',
                              style: Face.body
                                  .copyWith(fontWeight: FontWeight.w500)),
                          const SizedBox(height: Gap.sm),
                          _Explanation(
                              text: f.explanation.isEmpty
                                  ? (f.correct ? 'Correta.' : 'Incorreta.')
                                  : f.explanation,
                              right: f.correct),
                          const SizedBox(height: Gap.lg),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Column(
                children: [
                  ActionButton(
                    passed ? 'Continuar' : 'Tentar de novo',
                    tone: passed ? Wire.ack.color : Wire.syn.color,
                    onPressed: () => passed
                        ? context.go('/')
                        : context.pushReplacement('/quiz',
                            extra: widget.lesson),
                  ),
                  if (!passed) ...[
                    const SizedBox(height: Gap.sm),
                    TextButton(
                      onPressed: () => context.go('/'),
                      child: Text('Voltar para a trilha',
                          style: Face.meta.copyWith(color: Shade.textDim)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Enviado sem rede: a resposta está na fila e sobe sozinha.
class _Pending extends StatelessWidget {
  const _Pending();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Text('Respostas salvas', style: Face.display),
              const SizedBox(height: Gap.sm),
              Text(
                'Sem conexão agora. O questionário é corrigido assim que a rede '
                'voltar, e a trilha atualiza sozinha.',
                style: Face.body.copyWith(color: Shade.textDim),
              ),
              const Spacer(),
              ActionButton('Voltar para a trilha',
                  onPressed: () => context.go('/')),
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
  _HandshakePainter(this.t, this.passed, this.ackAt);
  final double t;
  final bool passed;
  final double ackAt;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 14.0;
    final right = size.width - 14;
    const rowH = 34.0;
    // O handshake usa o tempo até o ACK; o resto é da rajada.
    final hs = (t / ackAt).clamp(0.0, 1.0);

    final rail = Paint()
      ..color = Shade.rule
      ..strokeWidth = 1;
    canvas
      ..drawLine(const Offset(left, 0), Offset(left, size.height), rail)
      ..drawLine(Offset(right, 0), Offset(right, size.height), rail);

    final steps = [
      (
        y: rowH * 0.5,
        from: left,
        to: right,
        label: 'SYN',
        tone: Wire.syn.color
      ),
      (
        y: rowH * 1.5,
        from: right,
        to: left,
        label: 'SYN-ACK',
        tone: Wire.syn.color
      ),
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
      final local = ((hs - i / 3) * 3).clamp(0.0, 1.0);
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
        tp.paint(canvas,
            Offset((left + right) / 2 - tp.width / 2, s.y - tp.height - 4));
      }

      if (local == 1) {
        canvas.drawCircle(Offset(s.to, s.y), 3.5, Paint()..color = s.tone);
      }
    }

    // Rajada: pacotes saindo do ACK. Só na aprovação — é a recompensa.
    final b = ((t - ackAt) / (1 - ackAt)).clamp(0.0, 1.0);
    if (!passed || b == 0 || b == 1) return;
    final origin = Offset(right, rowH * 2.5);
    final ease = Curves.easeOutCubic.transform(b);
    for (var k = 0; k < 16; k++) {
      final angle = math.pi / 2 + k * math.pi / 15; // leque para dentro da tela
      final dist = 20 + ease * (70 + (k % 4) * 22);
      final p = origin + Offset(math.cos(angle), -math.sin(angle)) * dist;
      final color = (k % 5 == 0 ? Wire.syn : Wire.ack).color;
      canvas.drawCircle(
          p, 3 * (1 - b) + 1, Paint()..color = color.withValues(alpha: 1 - b));
    }
    canvas.drawCircle(
      origin,
      8 + ease * 40,
      Paint()
        ..color = Wire.ack.color.withValues(alpha: (1 - b) * 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_HandshakePainter old) =>
      old.t != t || old.passed != passed || old.ackAt != ackAt;
}

class _Explanation extends StatelessWidget {
  const _Explanation({required this.text, required this.right});
  final String text;
  final bool right;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: Shade.surfaceLow,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
              color: right ? Wire.ack.color : Wire.rst.color, width: 3),
        ),
      ),
      child: Text(text, style: Face.body.copyWith(color: Shade.textDim)),
    );
  }
}

/// Anel do nível enchendo do XP de antes até o de agora.
class _LevelUp extends StatelessWidget {
  const _LevelUp({required this.before, required this.after});
  final int before;
  final int after;

  @override
  Widget build(BuildContext context) {
    final from = levelProgress(before);
    final to = levelProgress(after);
    final up = to.level > from.level;

    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: Shade.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          LevelRing(
            level: to.level,
            // Subiu de nível: o anel parte do zero do nível novo.
            from: up ? 0 : from.progress,
            progress: to.progress,
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    up
                        ? 'Você chegou ao nível ${to.level}'
                        : 'Nível ${to.level}',
                    style: Face.title
                        .copyWith(color: up ? Wire.ack.color : Shade.text)),
                const SizedBox(height: 2),
                Text('${to.toNext} XP para o nível ${to.level + 1}',
                    style: Face.meta),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
