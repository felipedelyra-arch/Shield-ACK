import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/providers.dart';
import '../../../../domain/entities/learning.dart';
import '../../../../domain/entities/quiz_submission.dart';
import '../../../failure_text.dart';
import '../../../theme.dart';
import '../../../widgets/trace.dart';

/// Questionário.
///
/// Uma questão por vez, opções como linhas selecionáveis e não como cartões:
/// cartão sugere que cada opção é um objeto independente, quando na verdade são
/// alternativas mutuamente exclusivas de uma coisa só.
///
/// A correção é do servidor: o gabarito nunca chega ao aparelho, então acerto e
/// explicação só aparecem no resultado, depois do envio.
class QuizPage extends ConsumerStatefulWidget {
  const QuizPage({required this.lesson, super.key});
  final Lesson lesson;

  @override
  ConsumerState<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends ConsumerState<QuizPage> {
  final _clock = Stopwatch();
  final _answers = <String, Object>{};
  List<Question>? _questions;
  String? _error;
  int _index = 0;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r =
        await ref.read(quizRepositoryProvider).questions(widget.lesson.id);
    if (!mounted) return;
    setState(() => r.fold((f) => _error = failureText(f), (qs) {
          _questions = qs;
          _clock.start();
        }));
  }

  Future<void> _submit(List<Question> qs) async {
    setState(() => _sending = true);
    final r = await ref.read(quizRepositoryProvider).submit(QuizSubmission(
          lessonId: widget.lesson.id,
          clientElapsedMs: _clock.elapsedMilliseconds,
          answers: [
            for (final q in qs)
              QuizAnswer(questionId: q.id, value: _answers[q.id]!)
          ],
        ));
    if (!mounted) return;
    r.fold(
      (f) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failureText(f))));
      },
      (outcome) => context
          .pushReplacement('/result', extra: (widget.lesson, qs, outcome)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final qs = _questions;
    if (qs == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Text(_error!, style: Face.body),
        ),
      );
    }

    final q = qs[_index];
    final isLast = _index == qs.length - 1;
    final answered = _answers.containsKey(q.id);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.close), onPressed: () => context.pop()),
        title: Text('${_index + 1} de ${qs.length}',
            style: Face.figure.copyWith(color: Shade.textDim)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: LinearProgressIndicator(
            value: _answers.length / qs.length,
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
                  if (q.code != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(Gap.md),
                      decoration: BoxDecoration(
                        color: Shade.surfaceLow,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Shade.rule),
                      ),
                      child: Text(q.code!,
                          style: Face.code
                              .copyWith(fontSize: 12, color: Shade.textDim)),
                    ),
                    const SizedBox(height: Gap.lg),
                  ],
                  Text(q.prompt, style: Face.title.copyWith(height: 1.35)),
                  const SizedBox(height: Gap.lg),
                  _AnswerInput(
                    key: ValueKey(q.id),
                    question: q,
                    value: _answers[q.id],
                    onChanged: (v) => setState(() =>
                        v == null ? _answers.remove(q.id) : _answers[q.id] = v),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: ActionButton(
                isLast ? 'Enviar respostas' : 'Próxima',
                busy: _sending,
                onPressed: !answered
                    ? null
                    : isLast
                        ? () => _submit(qs)
                        : () => setState(() => _index++),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Entrada por tipo. O formato do valor é o que `functions/src/lib/grading.ts` espera.
class _AnswerInput extends StatelessWidget {
  const _AnswerInput({
    required this.question,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final Question question;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    final q = question;
    switch (q.type) {
      case QuestionType.single:
      case QuestionType.boolean:
        final options = q.type == QuestionType.boolean && q.options.isEmpty
            ? const ['Verdadeiro', 'Falso']
            : q.options;
        // V/F: a primeira opção é "verdadeiro".
        Object valueOf(int i) => q.type == QuestionType.boolean ? i == 0 : i;
        return Column(children: [
          for (var i = 0; i < options.length; i++)
            _Option(
              label: options[i],
              selected: value == valueOf(i),
              onTap: () => onChanged(valueOf(i)),
            ),
        ]);

      case QuestionType.fill:
        return TextFormField(
          initialValue: value as String?,
          autocorrect: false,
          enableSuggestions: false,
          style: Face.code,
          decoration: const InputDecoration(hintText: r'$ '),
          onChanged: (t) => onChanged(t.trim().isEmpty ? null : t),
        );

      case QuestionType.order:
        // Começa na ordem apresentada; já conta como resposta.
        final order =
            (value as List<int>?) ?? List.generate(q.options.length, (i) => i);
        if (value == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => onChanged(order));
        }
        return ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          onReorderItem: (from, to) {
            final next = [...order];
            next.insert(to, next.removeAt(from));
            onChanged(next);
          },
          children: [
            for (final i in order)
              ListTile(
                key: ValueKey(i),
                title: Text(q.options[i], style: Face.code),
                trailing: const Icon(Icons.drag_handle),
              ),
          ],
        );

      case QuestionType.match:
        final picks =
            (value as List<int?>?) ?? List<int?>.filled(q.prompts.length, null);
        return Column(children: [
          for (var i = 0; i < q.prompts.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: Row(children: [
                Expanded(child: Text(q.prompts[i], style: Face.body)),
                const SizedBox(width: Gap.sm),
                DropdownButton<int>(
                  value: picks[i],
                  hint: const Text('escolher'),
                  items: [
                    for (var j = 0; j < q.options.length; j++)
                      DropdownMenuItem(value: j, child: Text(q.options[j])),
                  ],
                  onChanged: (j) {
                    final next = [...picks]..[i] = j;
                    // Só vale como resposta quando todos os itens têm par.
                    onChanged(next.contains(null) ? null : next.cast<int>());
                  },
                ),
              ]),
            ),
        ]);
    }
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.label, required this.selected, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Material(
        color: Shade.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: selected ? Shade.text : Shade.rule,
                  width: selected ? 1.5 : 1),
            ),
            child: Text(label, style: Face.body),
          ),
        ),
      ),
    );
  }
}
