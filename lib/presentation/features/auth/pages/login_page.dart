import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../theme.dart';
import '../../../widgets/trace.dart';

/// Entrada.
///
/// Sem ilustração e sem promessa de marketing: o público deste app já sabe o
/// que veio fazer. A tela diz o que a pessoa vai aprender e sai da frente.
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Text('Shield Ack', style: Face.display.copyWith(fontSize: 40)),
              const SizedBox(height: Gap.md),
              SizedBox(
                width: 320,
                child: Text(
                  'Redes, segurança e DevSecOps em aulas curtas, com questionário '
                  'depois de cada uma. Quinze minutos por dia sustentam a sequência.',
                  style: Face.body.copyWith(color: Shade.textDim),
                ),
              ),
              const Spacer(),
              ActionButton('Entrar com Google',
                  onPressed: () => context.go('/')),
              const SizedBox(height: Gap.sm),
              ActionButton('Usar e-mail e senha',
                  tone: Shade.surface, onPressed: () => context.go('/')),
              const SizedBox(height: Gap.lg),
              Center(
                child: SizedBox(
                  width: 300,
                  child: Text(
                    'Ao entrar você aceita a política de privacidade. '
                    'Seu e-mail nunca é mostrado para outros alunos.',
                    textAlign: TextAlign.center,
                    style: Face.meta
                        .copyWith(fontSize: 12, color: Shade.textFaint),
                  ),
                ),
              ),
              const SizedBox(height: Gap.sm),
            ],
          ),
        ),
      ),
    );
  }
}
