import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/providers.dart';
import '../../../../domain/entities/learning.dart';
import '../../../theme.dart';
import '../../../widgets/trace.dart';

/// A trilha, lida como um trace de pacotes.
///
/// No topo, o que prende: nível subindo, sequência de dias e o cartão
/// "Continuar", que leva ao próximo passo com um toque. Abaixo, o trace — a régua
/// com nós de estado diz o estado sem legenda: cheio = fechou, meio = em
/// andamento, X = derrubado, vazio = ainda não chegou lá.
class TracksPage extends ConsumerWidget {
  const TracksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(tracksProvider);
    final profile = ref.watch(profileProvider).value;

    return Scaffold(
      body: SafeArea(
        child: switch (tracks) {
          AsyncData(value: final list) => _Content(list, profile),
          AsyncError() => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off_rounded,
                      size: 40, color: Wire.rst.color),
                  const SizedBox(height: Gap.md),
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

class _Content extends StatelessWidget {
  const _Content(this.tracks, this.profile);
  final List<Track> tracks;
  final Profile? profile;

  /// Próximo passo: o que está pela metade vem antes do que só está liberado.
  (Track, Lesson)? get _next {
    for (final wanted in [
      {LessonStatus.inProgress, LessonStatus.failed},
      {LessonStatus.available},
    ]) {
      for (final t in tracks) {
        for (final l in t.lessons) {
          if (wanted.contains(l.status)) return (t, l);
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final next = _next;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _Header(profile)),
        if (next != null)
          SliverToBoxAdapter(child: _ContinueCard(next.$1, next.$2)),
        if (tracks.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: Text('Nenhuma trilha publicada ainda.', style: Face.meta),
            ),
          ),
        for (final track in tracks) ...[
          SliverToBoxAdapter(child: _TrackHeader(track: track)),
          SliverList.builder(
            itemCount: track.lessons.length,
            itemBuilder: (context, i) {
              final lesson = track.lessons[i];
              return TraceSegment(
                state: lesson.status.wire,
                first: i == 0,
                last: i == track.lessons.length - 1,
                pulse: identical(lesson, next?.$2),
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
  const _Header(this.profile);
  final Profile? profile;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final lv = levelProgress(p?.xp ?? 0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.lg, Gap.md, Gap.md),
      child: Row(
        children: [
          LevelRing(level: lv.level, progress: p == null ? 0 : lv.progress),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p == null || p.displayName.isEmpty
                      ? 'Shield Ack'
                      : 'Olá, ${p.displayName}',
                  style: Face.title,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  p == null
                      ? ' '
                      : '${lv.toNext} XP para o nível ${lv.level + 1}',
                  style: Face.meta,
                ),
              ],
            ),
          ),
          StatChip(
            icon: Icons.local_fire_department_rounded,
            value: '${p?.streakDays ?? 0}',
            tone: (p?.streakDays ?? 0) > 0 ? Wire.syn : Wire.idle,
            semantics: '${p?.streakDays ?? 0} dias seguidos',
          ),
          const SizedBox(width: Gap.sm),
          StatChip(
            icon: Icons.favorite_rounded,
            value: '${p?.hearts ?? 5}',
            tone: Wire.rst,
            semantics: '${p?.hearts ?? 5} vidas',
          ),
        ],
      ),
    );
  }
}

/// O cartão que manda para a próxima aula. É o único elemento com brilho na tela.
class _ContinueCard extends StatelessWidget {
  const _ContinueCard(this.track, this.lesson);
  final Track track;
  final Lesson lesson;

  @override
  Widget build(BuildContext context) {
    final started = lesson.resumeAtSec > 0;
    final progress = lesson.durationSec == 0
        ? 0.0
        : (lesson.resumeAtSec / lesson.durationSec).clamp(0.0, 1.0);
    final retry = lesson.status == LessonStatus.failed;
    final tone = retry ? Wire.rst : Wire.ack;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.md),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => context.push('/lesson', extra: lesson),
          child: Ink(
            padding: const EdgeInsets.all(Gap.md + 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Shade.raised,
                  Color.alphaBlend(
                      tone.color.withValues(alpha: 0.14), Shade.surface),
                ],
              ),
              border: Border.all(color: tone.color.withValues(alpha: 0.35)),
              boxShadow: tone.glow(0.6),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        retry
                            ? 'Refazer o questionário'
                            : started
                                ? 'Continuar de onde parou'
                                : 'Próxima aula',
                        style: Face.meta.copyWith(color: tone.color),
                      ),
                      const SizedBox(height: Gap.xs),
                      Text(lesson.title,
                          style: Face.title.copyWith(fontSize: 19),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: Gap.sm),
                      Row(
                        children: [
                          _IconFact(Icons.lan_rounded, track.title),
                          const SizedBox(width: Gap.md),
                          _IconFact(
                              Icons.bolt_rounded, '${lesson.xpReward} XP'),
                        ],
                      ),
                      if (started && !retry) ...[
                        const SizedBox(height: Gap.md),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 4,
                            backgroundColor: Shade.rule,
                            valueColor: AlwaysStoppedAnimation(tone.color),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: Gap.md),
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: tone.color,
                    shape: BoxShape.circle,
                    boxShadow: tone.glow(),
                  ),
                  child: Icon(
                    retry ? Icons.replay_rounded : Icons.play_arrow_rounded,
                    color: Shade.base,
                    size: 32,
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

class _IconFact extends StatelessWidget {
  const _IconFact(this.icon, this.text, {this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Shade.textDim;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: c),
        const SizedBox(width: 4),
        Text(text, style: Face.meta.copyWith(color: c)),
      ],
    );
  }
}

class _TrackHeader extends StatelessWidget {
  const _TrackHeader({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) {
    final total = math.max(1, track.lessons.length);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.lg, Gap.md, Gap.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                  child: Text(track.title,
                      style: Face.display.copyWith(fontSize: 24))),
              Text('${track.done} de ${track.lessons.length}',
                  style: Face.figure.copyWith(color: Shade.textDim)),
            ],
          ),
          const SizedBox(height: Gap.xs),
          Text(track.blurb, style: Face.meta),
          const SizedBox(height: Gap.sm),
          TweenAnimationBuilder<double>(
            tween: Tween(end: track.done / total),
            duration: reduceMotion(context)
                ? Duration.zero
                : const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: v,
                minHeight: 4,
                backgroundColor: Shade.surface,
                valueColor: AlwaysStoppedAnimation(Wire.ack.color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LessonRow extends StatelessWidget {
  const _LessonRow({required this.lesson});
  final Lesson lesson;

  String _mmss(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  String get _minutes => '${(lesson.durationSec / 60).ceil()} min';

  /// A linha de apoio diz o que fazer em seguida, não o estado em abstrato.
  /// "Parou em 4:12" é acionável; "em progresso" não é.
  Widget get _detail => switch (lesson.status) {
        LessonStatus.completed => _IconFact(
            Icons.check_circle_rounded, 'Concluída',
            color: Wire.ack.color),
        LessonStatus.inProgress => _IconFact(
            Icons.play_circle_rounded, 'Parou em ${_mmss(lesson.resumeAtSec)}',
            color: Wire.syn.color),
        LessonStatus.failed => _IconFact(
            Icons.replay_rounded, 'Refazer o questionário',
            color: Wire.rst.color),
        LessonStatus.available => Row(children: [
            _IconFact(Icons.schedule_rounded, _minutes),
            const SizedBox(width: Gap.md),
            _IconFact(Icons.bolt_rounded, '${lesson.xpReward} XP',
                color: Wire.syn.color),
          ]),
        LessonStatus.locked => _IconFact(
            Icons.lock_rounded, 'Libera ao concluir a anterior',
            color: Shade.textFaint),
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          lesson.title,
          style: Face.body.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: lesson.locked ? Shade.textFaint : Shade.text,
          ),
        ),
        const SizedBox(height: 4),
        _detail,
      ],
    );
  }
}
