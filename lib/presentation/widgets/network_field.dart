import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Rede viva: hosts ligados por enlaces, pacotes trafegando, e um nó central —
/// o aluno — que pulsa. É a abertura do app e a única animação que não responde
/// a um toque; por isso só existe na tela de entrada.
///
/// Os pacotes usam as cores de estado do app: a maioria ACK, alguns SYN e raros
/// RST. A cena já ensina a legenda que a trilha usa depois.
class NetworkField extends StatefulWidget {
  const NetworkField({super.key});

  @override
  State<NetworkField> createState() => _NetworkFieldState();
}

class _NetworkFieldState extends State<NetworkField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );
  final _graph = _Graph.build(seed: 443);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sem movimento: um quadro fixo, bonito por si só.
    if (reduceMotion(context)) {
      _clock
        ..stop()
        ..value = 0.37;
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _clock,
        builder: (_, __) => CustomPaint(
          painter: _NetworkPainter(_graph, _clock.value),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _Node {
  _Node(this.x, this.y, this.r, this.drift);
  final double x, y, r, drift; // posição normalizada 0..1
}

class _Edge {
  _Edge(this.a, this.b, this.phase, this.speed, this.wire);
  final int a, b;
  final double phase, speed;
  final Wire wire;
}

class _Graph {
  _Graph(this.nodes, this.edges);
  final List<_Node> nodes;
  final List<_Edge> edges;

  /// Semente fixa: a mesma topologia em todo boot, como um diagrama de rede real.
  factory _Graph.build({required int seed}) {
    final rnd = math.Random(seed);
    final nodes = <_Node>[_Node(0.5, 0.52, 7, 0)]; // o aluno, no centro
    while (nodes.length < 26) {
      final x = 0.06 + rnd.nextDouble() * 0.88;
      final y = 0.14 + rnd.nextDouble() * 0.78; // longe da barra de status
      // Espaço mínimo: nós colados viram borrão.
      if (nodes.any((n) => (n.x - x).abs() < 0.1 && (n.y - y).abs() < 0.08)) {
        continue;
      }
      nodes.add(_Node(x, y, 2.5 + rnd.nextDouble() * 2, rnd.nextDouble() * 6));
    }

    final edges = <_Edge>[];
    final seen = <String>{};
    for (var i = 0; i < nodes.length; i++) {
      // Cada host liga aos 3 vizinhos mais próximos; o centro, aos 6. Vizinho
      // próximo dá malha, não polígono de linhas longas.
      final near = [
        for (var j = 0; j < nodes.length; j++)
          if (j != i) j
      ]..sort(
          (p, q) => _d(nodes[i], nodes[p]).compareTo(_d(nodes[i], nodes[q])));
      for (final j in near.take(i == 0 ? 6 : 3)) {
        final key = i < j ? '$i-$j' : '$j-$i';
        if (!seen.add(key)) continue;
        final roll = rnd.nextDouble();
        edges.add(_Edge(
          i,
          j,
          rnd.nextDouble(),
          rnd.nextBool() ? 1 : 2,
          roll < 0.08
              ? Wire.rst
              : roll < 0.3
                  ? Wire.syn
                  : Wire.ack,
        ));
      }
    }
    return _Graph(nodes, edges);
  }

  static double _d(_Node a, _Node b) =>
      math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2).toDouble();
}

class _NetworkPainter extends CustomPainter {
  _NetworkPainter(this.g, this.t);
  final _Graph g;
  final double t;

  Offset _at(_Node n, Size s) {
    // Deriva lenta, para a rede respirar sem virar protetor de tela.
    final a = (t * 2 * math.pi) + n.drift;
    return Offset(
      n.x * s.width + math.sin(a) * 3,
      n.y * s.height + math.cos(a * 0.8) * 3,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pos = [for (final n in g.nodes) _at(n, size)];

    final link = Paint()
      ..color = Shade.rule
      ..strokeWidth = 1;
    for (final e in g.edges) {
      canvas.drawLine(pos[e.a], pos[e.b], link);
    }

    for (final e in g.edges) {
      final p = (t * e.speed + e.phase) % 1.0;
      final from = pos[e.a], to = pos[e.b];
      final head = Offset.lerp(from, to, p)!;
      final tail = Offset.lerp(from, to, math.max(0, p - 0.12))!;

      canvas.drawLine(
        tail,
        head,
        Paint()
          ..shader = LinearGradient(
            colors: [e.wire.color.withValues(alpha: 0), e.wire.color],
          ).createShader(Rect.fromPoints(tail, head))
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(
        head,
        5,
        Paint()
          ..color = e.wire.color.withValues(alpha: 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(head, 2, Paint()..color = e.wire.color);
    }

    for (var i = 1; i < g.nodes.length; i++) {
      canvas
        ..drawCircle(pos[i], g.nodes[i].r, Paint()..color = Shade.surface)
        ..drawCircle(
            pos[i],
            g.nodes[i].r,
            Paint()
              ..color = Shade.textFaint
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2);
    }

    // O aluno: três ondas saindo, como um anúncio na rede.
    final c = pos[0];
    final ack = Wire.ack.color;
    for (var k = 0; k < 3; k++) {
      final wave = (t * 3 + k / 3) % 1.0;
      canvas.drawCircle(
        c,
        10 + wave * 46,
        Paint()
          ..color = ack.withValues(alpha: (1 - wave) * 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    canvas
      ..drawCircle(
          c,
          18,
          Paint()
            ..color = ack.withValues(alpha: 0.3)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12))
      ..drawCircle(c, 9, Paint()..color = ack)
      ..drawCircle(c, 4, Paint()..color = Shade.base);
  }

  @override
  bool shouldRepaint(_NetworkPainter old) => old.t != t;
}
