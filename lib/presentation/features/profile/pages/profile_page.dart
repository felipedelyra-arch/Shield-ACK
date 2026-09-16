import 'package:flutter/material.dart';

import '../../../../demo/demo_state.dart';
import '../../../theme.dart';
import '../../../widgets/trace.dart';

/// Perfil e ajustes numa tela só.
///
/// Os itens são nomeados pelo que a pessoa faz, não pelo que o sistema guarda:
/// "Baixar meus dados", não "Exportar payload LGPD".
class ProfilePage extends StatelessWidget {
  const ProfilePage({required this.demo, super.key});
  final DemoState demo;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: demo,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Perfil')),
        body: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(demo.displayName, style: Face.display),
                  const SizedBox(height: Gap.xs),
                  Text('Nível ${demo.level}', style: Face.meta),
                  const SizedBox(height: Gap.lg),
                  Row(
                    children: [
                      Field(value: '${demo.xp}', label: 'XP total'),
                      const SizedBox(width: Gap.xl),
                      Field(
                        value: '${demo.streak}',
                        label: 'dias seguidos',
                        tone: Wire.syn.color,
                      ),
                      const SizedBox(width: Gap.xl),
                      Field(
                        value: '${demo.tracks.expand((t) => t.lessons).where((l) => l.state == Wire.ack).length}',
                        label: 'aulas',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(),
            const _Item('Notificações', 'Lembretes, streak em risco, desafios'),
            const _Item('Bloqueio por biometria', 'Pedir ao abrir dados da conta'),
            const _Item('Downloads', 'Aulas salvas para assistir sem rede'),
            const Divider(),
            const _Item('Baixar meus dados', 'Recebe um arquivo com tudo que guardamos'),
            const _Item('Excluir minha conta', 'Apaga tudo, sem volta', tone: true),
            const Divider(),
            const _Item('Sair', 'Encerra a sessão neste aparelho'),
            const SizedBox(height: Gap.xl),
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item(this.title, this.detail, {this.tone = false});
  final String title;
  final String detail;
  final bool tone;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Face.body.copyWith(color: tone ? Wire.rst.color : Shade.text)),
            const SizedBox(height: 2),
            Text(detail, style: Face.meta),
          ],
        ),
      ),
    );
  }
}
