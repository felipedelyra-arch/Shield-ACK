import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../demo/demo_state.dart';
import '../../../theme.dart';
import '../../../widgets/trace.dart';

/// A trilha, lida como um trace de pacotes.
///
/// A régua vertical com nós de estado substitui o caminho serpenteado de bolhas
/// porque o conteúdo É uma sequência e o público lê traces o dia inteiro. O nó
/// diz o estado sem precisar de legenda: cheio = fechou, meio = em andamento,
/// X = derrubado, vazio = ainda não chegou lá.
class TracksPage extends StatelessWidget {
  const TracksPage({required this.demo, super.key});
  final DemoState demo;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: demo,
      builder: (context, _) => Scaffold(
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _Header(demo: demo)),
              for (final track in demo.tracks) ...[
                SliverToBoxAdapter(child: _TrackHeader(track: track)),
                SliverList.builder(
                  itemCount: track.lessons.length,
                  itemBuilder: (context, i) {
                    final lesson = track.lessons[i];
                    return TraceSegment(
                      state: lesson.state,
                      first: i == 0,
                      last: i == track.lessons.length - 1,
                      onTap: lesson.locked
                          ? null
                          : () => context.push('/lesson', extra: lesson),
                      child: _LessonRow(lesson: lesson),
                    );
                  },
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: Gap.xl)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.demo});
  final DemoState demo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.lg, Gap.md, Gap.lg),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Shield Ack', style: Face.display),
                const SizedBox(height: Gap.xs),
                Text('Nível ${demo.level}', style: Face.meta),
              ],
            ),
          ),
          Field(value: '${demo.xp}', label: 'XP'),
          const SizedBox(width: Gap.lg),
          Field(
            value: '${demo.streak}',
            label: demo.streak == 1 ? 'dia' : 'dias',
            tone: demo.streak > 0 ? Wire.syn.color : null,
          ),
          const SizedBox(width: Gap.lg),
          Field(
            value: '${demo.hearts}',
            label: demo.hearts == 1 ? 'vida' : 'vidas',
            tone: demo.hearts <= 1 ? Wire.rst.color : null,
          ),
        ],
      ),
    );
  }
}

class _TrackHeader extends StatelessWidget {
  const _TrackHeader({required this.track});
  final DemoTrack track;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.lg, Gap.md, Gap.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text(track.title, style: Face.title)),
              Text('${track.done}/${track.lessons.length}',
                  style: Face.figure.copyWith(color: Shade.textDim)),
            ],
          ),
          const SizedBox(height: Gap.xs),
          Text(track.blurb, style: Face.meta),
        ],
      ),
    );
  }
}

class _LessonRow extends StatelessWidget {
  const _LessonRow({required this.lesson});
  final DemoLesson lesson;

  String _mmss(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  /// A linha de apoio diz o que fazer em seguida, não o estado em abstrato.
  /// "parou em 4:12" é acionável; "em progresso" não é.
  String get _detail => switch (lesson.state) {
        Wire.ack => '${_mmss(lesson.durationSec)} · concluída',
        Wire.syn => 'parou em ${_mmss(lesson.resumeAtSec)}',
        Wire.rst => 'refazer o questionário',
        Wire.idle => '${_mmss(lesson.durationSec)} · ${lesson.xpReward} XP',
      };

  @override
  Widget build(BuildContext context) {
    final dim = lesson.locked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          lesson.title,
          style: Face.body.copyWith(
            fontWeight: FontWeight.w500,
            color: dim ? Shade.textFaint : Shade.text,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _detail,
          style: Face.meta.copyWith(
            color: lesson.state == Wire.idle ? Shade.textFaint : lesson.state.color,
          ),
        ),
      ],
    );
  }
}
