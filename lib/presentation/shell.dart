import 'package:flutter/material.dart';

import '../demo/demo_state.dart';
import 'features/duel/pages/duel_page.dart';
import 'features/friends/pages/ranking_page.dart';
import 'features/profile/pages/profile_page.dart';
import 'features/tracks/pages/tracks_page.dart';
import 'theme.dart';

/// Casca com as quatro superfícies do app.
///
/// Quatro é o teto: acima disso a barra vira gaveta de coisas que ninguém acha.
/// Notificações e ajustes não ganham aba — vivem dentro de Perfil, que é onde
/// a pessoa procura por elas.
class Shell extends StatefulWidget {
  const Shell({required this.demo, super.key});
  final DemoState demo;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          TracksPage(demo: widget.demo),
          DuelPage(demo: widget.demo),
          RankingPage(demo: widget.demo),
          ProfilePage(demo: widget.demo),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: Shade.surfaceLow,
        indicatorColor: Wire.ack.color.withValues(alpha: 0.15),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => Face.meta.copyWith(
            fontSize: 11,
            color: s.contains(WidgetState.selected) ? Shade.text : Shade.textFaint,
          ),
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.timeline_outlined), selectedIcon: Icon(Icons.timeline),
            label: 'Trilha'),
          NavigationDestination(
            icon: Icon(Icons.bolt_outlined), selectedIcon: Icon(Icons.bolt),
            label: 'Duelos'),
          NavigationDestination(
            icon: Icon(Icons.group_outlined), selectedIcon: Icon(Icons.group),
            label: 'Amigos'),
          NavigationDestination(
            icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person),
            label: 'Perfil'),
        ],
      ),
    );
  }
}
