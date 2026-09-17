import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Um segmento do trace: o nó de estado, a régua que o liga ao próximo, e o
/// conteúdo à direita.
///
/// A régua vertical não é ornamento — o conteúdo É uma sequência (a lição N só
/// libera depois da N-1), e é isso que o desenho está dizendo. Por isso ela
/// aparece na trilha e no duelo, e não aparece na lista de amigos.
class TraceSegment extends StatelessWidget {
  const TraceSegment({
    required this.state,
    required this.child,
    this.first = false,
    this.last = false,
    this.pulse = false,
    this.onTap,
    super.key,
  });

  final Wire state;
  final Widget child;
  final bool first;
  final bool last;

  /// O próximo passo do aluno. Só um nó pulsa por tela: é para onde o olho vai.
  final bool pulse;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 48,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter:
                          _RulePainter(state: state, first: first, last: last),
                    ),
                  ),
                  if (pulse)
                    Positioned(
                      left: 24 - 20,
                      top: _RulePainter._cy - 20,
                      child: _Pulse(color: state.color),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(
                  right: Gap.md,
                  top: Gap.md,
                  bottom: Gap.md,
                ),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.color});
  final Color color;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduceMotion(context) ? _c.stop() : _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          size: const Size(40, 40),
          painter: _PulsePainter(_c.value, widget.color),
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawCircle(
      c,
      7 + t * 13,
      Paint()
        ..color = color.withValues(alpha: (1 - t) * 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.t != t;
}

class _RulePainter extends CustomPainter {
  _RulePainter({required this.state, required this.first, required this.last});

  final Wire state;
  final bool first;
  final bool last;

  static const _cy =
      28.0; // centro do nó, alinhado com a primeira linha do título
  static const _r = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final rule = Paint()
      ..color = Shade.rule
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    if (!first) canvas.drawLine(Offset(x, 0), Offset(x, _cy - _r - 3), rule);
    if (!last) {
      canvas.drawLine(Offset(x, _cy + _r + 3), Offset(x, size.height), rule);
    }

    final c = Offset(x, _cy);
    switch (state) {
      // ACK: nó preenchido — o handshake fechou.
      case Wire.ack:
        canvas.drawCircle(c, _r, Paint()..color = state.color);
      // SYN: meio preenchido — enviado, aguardando resposta.
      case Wire.syn:
        canvas
          ..drawCircle(
              c,
              _r,
              Paint()
                ..color = state.color
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2)
          ..drawArc(Rect.fromCircle(center: c, radius: _r - 1), -1.5708, 3.1416,
              true, Paint()..color = state.color);
      // RST: cruz — a conexão foi derrubada.
      case Wire.rst:
        final p = Paint()
          ..color = state.color
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        canvas
          ..drawLine(c + const Offset(-4, -4), c + const Offset(4, 4), p)
          ..drawLine(c + const Offset(4, -4), c + const Offset(-4, 4), p);
      // Ainda não alcançado: contorno apagado.
      case Wire.idle:
        canvas.drawCircle(
            c,
            _r,
            Paint()
              ..color = Shade.rule
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_RulePainter old) =>
      old.state != state || old.first != first || old.last != last;
}

/// Contador de cabeçalho: valor grande, rótulo pequeno abaixo.
/// Usado para XP, streak e vidas — sempre nessa ordem, sempre com o mesmo peso.
class Field extends StatelessWidget {
  const Field({required this.value, required this.label, this.tone, super.key});

  final String value;
  final String label;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style:
                Face.figure.copyWith(fontSize: 19, color: tone ?? Shade.text)),
        Text(label,
            style: Face.meta.copyWith(fontSize: 12, color: Shade.textFaint)),
      ],
    );
  }
}

/// Botão de ação. Um só estilo primário no app inteiro — quando tudo pode ser
/// enfatizado, nada é. [outlined] é o secundário; [tone] troca a cor de fundo.
///
/// Afunda ao pressionar e dá um toque de vibração: a resposta vem no dedo,
/// antes da rede responder.
class ActionButton extends StatefulWidget {
  const ActionButton(
    this.label, {
    required this.onPressed,
    this.tone,
    this.icon,
    this.leading,
    this.outlined = false,
    this.busy = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? tone;
  final IconData? icon;

  /// Marca à esquerda quando um ícone do Material não serve.
  final Widget? leading;
  final bool outlined;
  final bool busy;

  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    final fill = widget.tone ?? Wire.ack.color;
    final bg = widget.outlined
        ? Colors.transparent
        : enabled || widget.busy
            ? fill
            : Shade.surface;
    // Texto escuro só sobre fundo claro.
    final fg = !enabled && !widget.busy
        ? Shade.textFaint
        : !widget.outlined && fill.computeLuminance() > 0.3
            ? Shade.base
            : Shade.text;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: enabled
            ? (_) {
                setState(() => _down = false);
                HapticFeedback.lightImpact();
                widget.onPressed!();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: const Duration(milliseconds: 90),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 56,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
              border: widget.outlined
                  ? Border.all(
                      color: enabled ? Shade.rule : Shade.surface, width: 1.5)
                  : null,
              boxShadow: enabled && !widget.outlined && widget.tone == null
                  ? Wire.ack.glow(_down ? 0.4 : 0.8)
                  : null,
            ),
            alignment: Alignment.center,
            child: widget.busy
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child:
                        CircularProgressIndicator(strokeWidth: 2.5, color: fg))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.leading != null) ...[
                        widget.leading!,
                        const SizedBox(width: Gap.sm + 2),
                      ] else if (widget.icon != null) ...[
                        Icon(widget.icon, color: fg, size: 22),
                        const SizedBox(width: Gap.sm),
                      ],
                      Flexible(
                        child: Text(
                          widget.label,
                          overflow: TextOverflow.ellipsis,
                          style: Face.body.copyWith(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: fg),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Estado vazio. Um convite para agir, nunca um encolher de ombros.
class Empty extends StatelessWidget {
  const Empty({required this.headline, required this.action, super.key});
  final String headline;
  final Widget action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(headline, style: Face.title),
            const SizedBox(height: Gap.lg),
            action,
          ],
        ),
      );
}

/// Nível dentro de um anel que enche até o próximo. Anima quando o XP muda —
/// é o retorno visual de cada aula concluída.
class LevelRing extends StatelessWidget {
  const LevelRing({
    required this.level,
    required this.progress,
    this.from,
    this.size = 56,
    super.key,
  });

  final int level;
  final double progress;

  /// Ponto de partida da animação na primeira exibição (ex.: XP antes do quiz).
  final double? from;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Nível $level, ${(progress * 100).round()}% para o próximo',
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: from, end: progress),
        duration: reduceMotion(context)
            ? Duration.zero
            : Duration(milliseconds: from == null ? 900 : 1600),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: _RingPainter(v),
            child: Center(
              child: Text('$level',
                  style: Face.title.copyWith(
                      fontSize: size * 0.36, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v);
  final double v;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(4);
    canvas.drawArc(
        r,
        0,
        6.2832,
        false,
        Paint()
          ..color = Shade.surface
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5);
    if (v <= 0) return;
    final ack = Wire.ack.color;
    canvas.drawArc(
      r,
      -1.5708,
      6.2832 * v,
      false,
      Paint()
        ..shader = SweepGradient(
          startAngle: -1.5708,
          endAngle: 4.7124,
          colors: [ack.withValues(alpha: 0.4), ack],
          transform: const GradientRotation(-1.5708),
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 5,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.v != v;
}

/// Contador compacto com ícone: sequência de dias, vidas.
class StatChip extends StatelessWidget {
  const StatChip({
    required this.icon,
    required this.value,
    required this.tone,
    required this.semantics,
    super.key,
  });

  final IconData icon;
  final String value;
  final Wire tone;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semantics,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: tone.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: tone.color),
            const SizedBox(width: 4),
            Text(value, style: Face.figure.copyWith(color: tone.color)),
          ],
        ),
      ),
    );
  }
}
