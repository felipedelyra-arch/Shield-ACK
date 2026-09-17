import 'package:flutter/material.dart';

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
    this.onTap,
    super.key,
  });

  final Wire state;
  final Widget child;
  final bool first;
  final bool last;
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
              width: 44,
              child: CustomPaint(
                painter: _RulePainter(state: state, first: first, last: last),
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
/// enfatizado, nada é.
class ActionButton extends StatelessWidget {
  const ActionButton(this.label,
      {required this.onPressed, this.tone, this.busy = false, super.key});

  final String label;
  final VoidCallback? onPressed;
  final Color? tone;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final color = tone ?? Wire.ack.color;
    final enabled = onPressed != null && !busy;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: Material(
        color: enabled ? color : Shade.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(10),
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Shade.textDim))
                : Text(label,
                    style: Face.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: enabled ? Shade.base : Shade.textFaint,
                    )),
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
