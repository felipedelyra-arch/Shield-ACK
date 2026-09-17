import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/providers.dart';
import '../../../theme.dart';
import '../../../widgets/trace.dart';

/// Perfil e ajustes numa tela só.
///
/// Os itens são nomeados pelo que a pessoa faz, não pelo que o sistema guarda:
/// "Baixar meus dados", não "Exportar payload LGPD".
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider).value;
    final done =
        ref.watch(tracksProvider).value?.fold<int>(0, (sum, t) => sum + t.done);

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p?.displayName ?? ' ', style: Face.display),
                const SizedBox(height: Gap.xs),
                Text(p == null ? ' ' : 'Nível ${p.level}', style: Face.meta),
                const SizedBox(height: Gap.lg),
                Row(
                  children: [
                    Field(value: '${p?.xp ?? '–'}', label: 'XP total'),
                    const SizedBox(width: Gap.xl),
                    Field(
                      value: '${p?.streakDays ?? '–'}',
                      label: 'dias seguidos',
                      tone: Wire.syn.color,
                    ),
                    const SizedBox(width: Gap.xl),
                    Field(value: '${done ?? '–'}', label: 'aulas'),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
          const _Item('Notificações', 'Lembretes, streak em risco, desafios'),
          const _Item(
              'Bloqueio por biometria', 'Pedir ao abrir dados da conta'),
          const _Item('Downloads', 'Aulas salvas para assistir sem rede'),
          const Divider(),
          const _Item(
              'Baixar meus dados', 'Recebe um arquivo com tudo que guardamos'),
          const _Item('Excluir minha conta', 'Apaga tudo, sem volta',
              tone: true),
          const Divider(),
          _Item(
            'Sair',
            'Encerra a sessão e apaga os dados deste aparelho',
            onTap: () async {
              await ref.read(authRepositoryProvider).signOut();
              if (context.mounted) context.go('/login');
            },
          ),
          const SizedBox(height: Gap.xl),
        ],
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item(this.title, this.detail, {this.tone = false, this.onTap});
  final String title;
  final String detail;
  final bool tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Face.body
                    .copyWith(color: tone ? Wire.rst.color : Shade.text)),
            const SizedBox(height: 2),
            Text(detail, style: Face.meta),
          ],
        ),
      ),
    );
  }
}
