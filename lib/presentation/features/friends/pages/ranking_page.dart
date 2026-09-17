import 'package:flutter/material.dart';

import '../../../../demo/demo_state.dart';
import '../../../theme.dart';
import '../../../widgets/trace.dart';

/// Amigos e ranking na mesma tela: a única razão de olhar a lista de amigos é
/// comparar-se com ela. Separar em duas abas seria fidelidade ao modelo de
/// dados, não ao que a pessoa quer.
///
/// Sem régua de trace aqui — ranking não é sequência causal, é ordenação. O
/// desenho não deve sugerir que uma posição libera a outra.
class RankingPage extends StatelessWidget {
  const RankingPage({required this.demo, super.key});
  final DemoState demo;

  @override
  Widget build(BuildContext context) {
    final ranked = [...demo.friends]..sort((a, b) => b.xp.compareTo(a.xp));

    return Scaffold(
      appBar: AppBar(title: const Text('Amigos')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.lg),
            child: Text('Esta semana', style: Face.meta),
          ),
          for (var i = 0; i < ranked.length; i++)
            _Row(rank: i + 1, friend: ranked[i]),
          const SizedBox(height: Gap.lg),
          Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Seu código', style: Face.meta),
                const SizedBox(height: Gap.xs),
                // Monoespaçada porque é um código para ditar e digitar, e o
                // alinhamento de caracteres ajuda a conferir.
                SelectableText(demo.friendCode,
                    style: Face.code.copyWith(fontSize: 22, letterSpacing: 3)),
                const SizedBox(height: Gap.sm),
                Text(
                  'Compartilhe para receber convites. Ninguém encontra você por e-mail.',
                  style: Face.meta,
                ),
                const SizedBox(height: Gap.md),
                ActionButton('Adicionar por código',
                    tone: Shade.surface, onPressed: () {}),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.rank, required this.friend});
  final int rank;
  final DemoFriend friend;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: friend.isMe ? Shade.surfaceLow : null,
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('$rank',
                style: Face.figure
                    .copyWith(color: rank <= 3 ? Shade.text : Shade.textFaint)),
          ),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(friend.name,
                      overflow: TextOverflow.ellipsis,
                      style: Face.body.copyWith(
                          fontWeight:
                              friend.isMe ? FontWeight.w600 : FontWeight.w400)),
                ),
                if (friend.online) ...[
                  const SizedBox(width: Gap.sm),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                        color: Wire.ack.color, shape: BoxShape.circle),
                  ),
                ],
              ],
            ),
          ),
          Text('${friend.streak}d',
              style:
                  Face.figure.copyWith(fontSize: 13, color: Shade.textFaint)),
          const SizedBox(width: Gap.md),
          SizedBox(
            width: 56,
            child: Text('${friend.xp}',
                textAlign: TextAlign.right,
                style: Face.figure.copyWith(color: Shade.text)),
          ),
        ],
      ),
    );
  }
}
