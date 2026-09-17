import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/providers.dart';
import '../../../../domain/entities/learning.dart';
import '../../../../domain/repositories/learning_repository.dart';
import '../../../failure_text.dart';
import '../../../theme.dart';
import '../../../widgets/trace.dart';

/// Player da aula.
///
/// Abrir a tela chama `startLesson`: é o servidor que autoriza, e sem essa chamada
/// o `submitQuiz` responde LESSON_LOCKED. O vídeo ainda é um retângulo — o player
/// HLS com `getLessonPlayback()` e `SecureScreen` é a próxima etapa.
class LessonPage extends ConsumerStatefulWidget {
  const LessonPage({required this.lesson, super.key});
  final Lesson lesson;

  @override
  ConsumerState<LessonPage> createState() => _LessonPageState();
}

class _LessonPageState extends ConsumerState<LessonPage> {
  // Guardado no initState: `ref` não pode ser usado no dispose.
  late final LearningRepository _repo = ref.read(learningRepositoryProvider);
  late int _atSec = widget.lesson.resumeAtSec;
  late int _reportedSec = widget.lesson.resumeAtSec;
  bool _authorized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repo.startLesson(widget.lesson.id).then((r) {
      if (!mounted) return;
      setState(() => r.fold(
            (f) => _error = failureText(f),
            (resumeAt) {
              _authorized = true;
              if (resumeAt > _atSec) _atSec = resumeAt;
            },
          ));
    });
  }

  @override
  void dispose() {
    _flushWatch();
    super.dispose();
  }

  /// Envia só o que avançou desde o último envio; o servidor guarda o máximo.
  void _flushWatch() {
    if (!_authorized || _atSec <= _reportedSec) return;
    _repo.reportWatch(widget.lesson.id, _atSec, _atSec - _reportedSec);
    _reportedSec = _atSec;
  }

  String _mmss(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l = widget.lesson;
    final pos = l.durationSec == 0 ? 0.0 : _atSec / l.durationSec;
    final canQuiz = _authorized && pos >= 0.9;

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
                  onPressed: _authorized
                      ? () => setState(() => _atSec =
                          (_atSec + l.durationSec ~/ 4).clamp(0, l.durationSec))
                      : null,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: Gap.md, vertical: Gap.sm),
            child: Row(
              children: [
                Text(_mmss(_atSec), style: Face.figure.copyWith(fontSize: 13)),
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
                      value: pos.clamp(0.0, 1.0),
                      onChanged: _authorized
                          ? (v) => setState(
                              () => _atSec = (v * l.durationSec).round())
                          : null,
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
                  if (_error != null) ...[
                    Text(_error!,
                        style: Face.body.copyWith(color: Wire.rst.color)),
                    const SizedBox(height: Gap.md),
                  ],
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
                canQuiz
                    ? 'Responder questionário'
                    : 'Assistir até o fim para liberar',
                busy: !_authorized && _error == null,
                // O desbloqueio real acontece na Function; aqui é só a UI
                // refletindo a mesma regra.
                onPressed: canQuiz
                    ? () {
                        _flushWatch();
                        context.push('/quiz', extra: l);
                      }
                    : null,
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
