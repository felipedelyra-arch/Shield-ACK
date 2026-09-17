import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../demo/demo_state.dart';
import '../../../theme.dart';
import '../../../widgets/trace.dart';

/// Player da aula.
///
/// Em produção, `SecureScreen` embrulha esta tela (FLAG_SECURE no Android) e a
/// URL vem de `getLessonPlayback()` com token de 120s. Na demo o vídeo é um
/// retângulo — o que está sendo avaliado aqui é o enquadramento, a retomada de
/// posição e o caminho para o questionário.
class LessonPage extends StatefulWidget {
  const LessonPage({required this.lesson, super.key});
  final DemoLesson lesson;

  @override
  State<LessonPage> createState() => _LessonPageState();
}

class _LessonPageState extends State<LessonPage> {
  late double _pos = widget.lesson.progress;

  String _mmss(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l = widget.lesson;
    final atSec = (l.durationSec * _pos).round();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        title: Text(l.title,
            style: Face.body.copyWith(fontWeight: FontWeight.w500)),
      ),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(
              color: Shade.surfaceLow,
              child: Center(
                child: IconButton(
                  iconSize: 56,
                  color: Shade.text,
                  icon: const Icon(Icons.play_circle_outline),
                  // Avança a posição para dar para exercitar a retomada.
                  onPressed: () =>
                      setState(() => _pos = (_pos + 0.25).clamp(0, 1)),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: Gap.md, vertical: Gap.sm),
            child: Row(
              children: [
                Text(_mmss(atSec), style: Face.figure.copyWith(fontSize: 13)),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      activeTrackColor: Wire.ack.color,
                      inactiveTrackColor: Shade.rule,
                      thumbColor: Wire.ack.color,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      value: _pos,
                      onChanged: (v) => setState(() => _pos = v),
                    ),
                  ),
                ),
                const SizedBox(width: Gap.sm),
                Text(_mmss(l.durationSec),
                    style: Face.figure
                        .copyWith(fontSize: 13, color: Shade.textDim)),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Gap.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.title, style: Face.title),
                  const SizedBox(height: Gap.md),
                  Text(
                    'Ao final desta aula você consegue ler um trace, identificar em que '
                    'ponto do handshake a conexão está e explicar por que ela não fechou.',
                    style: Face.body.copyWith(color: Shade.textDim),
                  ),
                  const SizedBox(height: Gap.lg),
                  const _Transcript(),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: ActionButton(
                _pos >= 0.9
                    ? 'Responder questionário'
                    : 'Assistir até o fim para liberar',
                // O desbloqueio real acontece na Function; aqui é só a UI
                // refletindo a mesma regra.
                onPressed:
                    _pos >= 0.9 ? () => context.push('/quiz', extra: l) : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Transcript extends StatelessWidget {
  const _Transcript();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: Shade.surfaceLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Shade.rule),
      ),
      // Monoespaçada aqui porque o conteúdo é saída real de terminal — não é
      // um rótulo de interface fantasiado de código.
      child: Text(
        r'$ tcpdump -ni eth0 "tcp port 443" -c 3'
        '\n'
        '10:14:02.118 IP 10.0.0.5.51234 > 93.184.216.34.443: Flags [S]\n'
        '10:14:02.142 IP 93.184.216.34.443 > 10.0.0.5.51234: Flags [S.]\n'
        '10:14:02.142 IP 10.0.0.5.51234 > 93.184.216.34.443: Flags [.]',
        style: Face.code.copyWith(fontSize: 12, color: Shade.textDim),
      ),
    );
  }
}
