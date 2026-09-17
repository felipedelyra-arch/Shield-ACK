import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/providers.dart';
import '../../../../domain/entities/learning.dart';
import '../../../theme.dart';
import '../../../widgets/trace.dart';

/// A trilha, lida como um trace de pacotes.
///
/// A régua vertical com nós de estado substitui o caminho serpenteado de bolhas
/// porque o conteúdo É uma sequência e o público lê traces o dia inteiro. O nó
/// diz o estado sem precisar de legenda: cheio = fechou, meio = em andamento,
/// X = derrubado, vazio = ainda não chegou lá.
class TracksPage extends ConsumerWidget {
  const TracksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(tracksProvider);
    final profile = ref.watch(profileProvider).value;

    return Scaffold(
      body: SafeArea(
        child: switch (tracks) {
          AsyncData(value: final list) => CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _Header(profile: profile)),
                if (list.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(Gap.md),
                      child: Text('Nenhuma trilha publicada ainda.',
                          style: Face.meta),
                    ),
                  ),
                for (final track in list) ...[
                  SliverToBoxAdapter(child: _TrackHeader(track: track)),
                  SliverList.builder(
                    itemCount: track.lessons.length,
                    itemBuilder: (context, i) {
                      final lesson = track.lessons[i];
                      return TraceSegment(
                        state: lesson.status.wire,
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
          AsyncError() => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Não deu para carregar a trilha.', style: Face.body),
                  const SizedBox(height: Gap.md),
                  TextButton(
                    onPressed: () => ref.invalidate(tracksProvider),
                    child: const Text('Tentar de novo'),
                  ),
                ],
              ),
            ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

extension on LessonStatus {
  Wire get wire => switch (this) {
        LessonStatus.completed => Wire.ack,
        LessonStatus.inProgress || LessonStatus.available => Wire.syn,
        LessonStatus.failed => Wire.rst,
        LessonStatus.locked => Wire.idle,
      };
}

class _Header extends StatelessWidget {
  const _Header({required this.profile});
  final Profile? profile;

  @override
  Widget build(BuildContext context) {
    final p = profile;
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
                Text(p == null ? ' ' : 'Nível ${p.level}', style: Face.meta),
              ],
            ),
          ),
          Field(value: '${p?.xp ?? '–'}', label: 'XP'),
          const SizedBox(width: Gap.lg),
          Field(
            value: '${p?.streakDays ?? '–'}',
            label: p?.streakDays == 1 ? 'dia' : 'dias',
            tone: (p?.streakDays ?? 0) > 0 ? Wire.syn.color : null,
          ),
          const SizedBox(width: Gap.lg),
          Field(
            value: '${p?.hearts ?? '–'}',
            label: p?.hearts == 1 ? 'vida' : 'vidas',
            tone: p != null && p.hearts <= 1 ? Wire.rst.color : null,
          ),
        ],
      ),
    );
  }
}

class _TrackHeader extends StatelessWidget {
  const _TrackHeader({required this.track});
  final Track track;

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
  final Lesson lesson;

  String _mmss(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  /// A linha de apoio diz o que fazer em seguida, não o estado em abstrato.
  /// "parou em 4:12" é acionável; "em progresso" não é.
  String get _detail => switch (lesson.status) {
        LessonStatus.completed => '${_mmss(lesson.durationSec)} · concluída',
        LessonStatus.inProgress => 'parou em ${_mmss(lesson.resumeAtSec)}',
        LessonStatus.failed => 'refazer o questionário',
        LessonStatus.available ||
        LessonStatus.locked =>
          '${_mmss(lesson.durationSec)} · ${lesson.xpReward} XP',
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
            color: dim ? Shade.textFaint : lesson.status.wire.color,
          ),
        ),
      ],
    );
  }
}
