import 'package:flutter/material.dart';

import '../../../../demo/demo_state.dart';
import '../../../theme.dart';
import '../../../widgets/trace.dart';

/// Duelos. A mesma régua de estado da trilha: quem está esperando quem.
///
/// "Sua vez" e "aguardando" são a informação que faz alguém abrir o app — não
/// o placar. Por isso é a linha de cima de cada item, na cor do estado.
class DuelPage extends StatelessWidget {
  const DuelPage({required this.demo, super.key});
  final DemoState demo;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: demo,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Duelos')),
        body: demo.duels.isEmpty
            ? Empty(
                headline:
                    'Nenhum duelo em aberto.\nDesafie alguém da sua lista.',
                action: ActionButton('Escolher adversário', onPressed: () {}),
              )
            : ListView(
                children: [
                  for (var i = 0; i < demo.duels.length; i++)
                    TraceSegment(
                      state: switch (demo.duels[i].turn) {
                        DuelTurn.yours => Wire.syn,
                        DuelTurn.theirs => Wire.idle,
                        DuelTurn.invite => Wire.ack,
                      },
                      first: i == 0,
                      last: i == demo.duels.length - 1,
                      onTap: () {},
                      child: _DuelRow(duel: demo.duels[i]),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(Gap.md),
                    child: ActionButton('Novo duelo',
                        tone: Shade.surface, onPressed: () {}),
                  ),
                ],
              ),
      ),
    );
  }
}

class _DuelRow extends StatelessWidget {
  const _DuelRow({required this.duel});
  final DemoDuel duel;

  ({String text, Color tone}) get _status => switch (duel.turn) {
        DuelTurn.yours => (
            text: 'Sua vez · rodada ${duel.round} de 5',
            tone: Wire.syn.color
          ),
        DuelTurn.theirs => (
            text: 'Aguardando ${duel.opponent}',
            tone: Shade.textFaint
          ),
        DuelTurn.invite => (
            text: '${duel.opponent} te desafiou',
            tone: Wire.ack.color
          ),
      };

  @override
  Widget build(BuildContext context) {
    final s = _status;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.text,
                  style: Face.meta
                      .copyWith(color: s.tone, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(duel.opponent,
                  style: Face.body.copyWith(fontWeight: FontWeight.w500)),
              Text(duel.track, style: Face.meta),
            ],
          ),
        ),
        if (duel.turn != DuelTurn.invite)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('${duel.myScore}',
                    style: Face.figure.copyWith(
                        fontSize: 22,
                        color: duel.myScore >= duel.theirScore
                            ? Shade.text
                            : Shade.textDim)),
                Text('  ·  ',
                    style: Face.meta.copyWith(color: Shade.textFaint)),
                Text('${duel.theirScore}',
                    style: Face.figure.copyWith(
                        fontSize: 22,
                        color: duel.theirScore > duel.myScore
                            ? Shade.text
                            : Shade.textDim)),
              ],
            ),
          ),
      ],
    );
  }
}
