import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../demo/demo_state.dart';
import '../../../theme.dart';
import '../../../widgets/trace.dart';

/// Questionário.
///
/// Uma questão por vez, opções como linhas selecionáveis e não como cartões:
/// cartão sugere que cada opção é um objeto independente, quando na verdade são
/// alternativas mutuamente exclusivas de uma coisa só.
///
/// O feedback aparece DEPOIS de confirmar, com a explicação sempre — inclusive
/// no acerto. Num app de segurança, acertar por sorte e seguir adiante é pior
/// do que errar.
class QuizPage extends StatefulWidget {
  const QuizPage({required this.lesson, required this.demo, super.key});
  final DemoLesson lesson;
  final DemoState demo;

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  int _index = 0;
  int? _picked;
  bool _revealed = false;
  int _correct = 0;

  DemoQuestion get _q => demoQuestions[_index];
  bool get _isLast => _index == demoQuestions.length - 1;

  void _confirm() {
    setState(() {
      _revealed = true;
      if (_picked == _q.correct) _correct++;
    });
  }

  void _next() {
    if (_isLast) {
      widget.demo.applyQuiz(
        lesson: widget.lesson,
        correct: _correct,
        total: demoQuestions.length,
      );
      context.pushReplacement('/result', extra: (_correct, demoQuestions.length, widget.lesson));
      return;
    }
    setState(() {
      _index++;
      _picked = null;
      _revealed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => context.pop()),
        title: Text('${_index + 1} de ${demoQuestions.length}',
            style: Face.figure.copyWith(color: Shade.textDim)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: LinearProgressIndicator(
            value: (_index + (_revealed ? 1 : 0)) / demoQuestions.length,
            minHeight: 2,
            backgroundColor: Shade.rule,
            valueColor: AlwaysStoppedAnimation(Wire.ack.color),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(Gap.md),
                children: [
                  if (_q.code != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(Gap.md),
                      decoration: BoxDecoration(
                        color: Shade.surfaceLow,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Shade.rule),
                      ),
                      child: Text(_q.code!,
                          style: Face.code.copyWith(fontSize: 12, color: Shade.textDim)),
                    ),
                    const SizedBox(height: Gap.lg),
                  ],
                  Text(_q.prompt, style: Face.title.copyWith(height: 1.35)),
                  const SizedBox(height: Gap.lg),
                  for (var i = 0; i < _q.options.length; i++)
                    _Option(
                      label: _q.options[i],
                      selected: _picked == i,
                      state: !_revealed
                          ? null
                          : i == _q.correct
                              ? Wire.ack
                              : (_picked == i ? Wire.rst : null),
                      onTap: _revealed ? null : () => setState(() => _picked = i),
                    ),
                  if (_revealed) ...[
                    const SizedBox(height: Gap.md),
                    _Explanation(text: _q.explanation, right: _picked == _q.correct),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: _revealed
                  ? ActionButton(_isLast ? 'Ver resultado' : 'Próxima', onPressed: _next)
                  : ActionButton('Confirmar', onPressed: _picked == null ? null : _confirm),
            ),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.label, required this.selected, required this.state, this.onTap});

  final String label;
  final bool selected;
  final Wire? state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tone = state?.color;
    final border = tone ?? (selected ? Shade.text : Shade.rule);

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Material(
        color: tone?.withValues(alpha: 0.08) ?? Shade.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border, width: selected || tone != null ? 1.5 : 1),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(label,
                      style: Face.body.copyWith(color: tone ?? Shade.text)),
                ),
                if (state == Wire.ack)
                  Icon(Icons.check, size: 18, color: Wire.ack.color)
                else if (state == Wire.rst)
                  Icon(Icons.close, size: 18, color: Wire.rst.color),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
          left: BorderSide(color: right ? Wire.ack.color : Wire.rst.color, width: 3),
        ),
      ),
      child: Text(text, style: Face.body.copyWith(color: Shade.textDim)),
    );
  }
}
