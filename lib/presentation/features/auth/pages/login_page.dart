import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../failure_text.dart';
import '../../../theme.dart';
import '../../../widgets/trace.dart';

/// Entrada.
///
/// Sem ilustração e sem promessa de marketing: o público deste app já sabe o
/// que veio fazer. A tela diz o que a pessoa vai aprender e sai da frente.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _emailMode = false;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<Result<Failure, void>> Function() action) async {
    setState(() => _busy = true);
    final r = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    r.fold(
      (f) {
        if (f case InvalidInputFailure(code: 'CANCELED')) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failureText(f))));
      },
      // Com Firebase o redirect do router já faz isto; na demo não há redirect.
      (_) => context.go('/'),
    );
  }

  /// Validação local só para poupar uma ida ao servidor. A política real de senha
  /// (tamanho, vazamento) é do Identity Platform.
  String? get _invalid {
    if (!_email.text.contains('@')) return 'Informe um e-mail válido.';
    if (_password.text.length < 8) {
      return 'A senha tem pelo menos 8 caracteres.';
    }
    return null;
  }

  void _withEmail(bool signUp) {
    final invalid = _invalid;
    if (invalid != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(invalid)));
      return;
    }
    final auth = ref.read(authRepositoryProvider);
    _run(() => signUp
        ? auth.signUpWithEmail(_email.text, _password.text)
        : auth.signInWithEmail(_email.text, _password.text));
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.read(authRepositoryProvider);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Gap.md),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                minHeight: MediaQuery.sizeOf(context).height - 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: Gap.xl * 2),
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
                const SizedBox(height: Gap.xl * 2),
                if (!_emailMode) ...[
                  ActionButton('Entrar com Google',
                      busy: _busy,
                      onPressed: () => _run(auth.signInWithGoogle)),
                  const SizedBox(height: Gap.sm),
                  ActionButton('Usar e-mail e senha',
                      tone: Shade.surface,
                      onPressed: _busy
                          ? null
                          : () => setState(() => _emailMode = true)),
                ] else
                  AutofillGroup(
                    child: Column(
                      children: [
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          autocorrect: false,
                          decoration:
                              const InputDecoration(labelText: 'E-mail'),
                        ),
                        const SizedBox(height: Gap.sm),
                        TextField(
                          controller: _password,
                          obscureText: true,
                          autofillHints: const [AutofillHints.password],
                          decoration: const InputDecoration(labelText: 'Senha'),
                          onSubmitted: (_) => _withEmail(false),
                        ),
                        const SizedBox(height: Gap.lg),
                        ActionButton('Entrar',
                            busy: _busy, onPressed: () => _withEmail(false)),
                        const SizedBox(height: Gap.sm),
                        ActionButton('Criar conta',
                            tone: Shade.surface,
                            onPressed: _busy ? null : () => _withEmail(true)),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _emailMode = false),
                          child: Text('Voltar',
                              style: Face.meta.copyWith(color: Shade.textDim)),
                        ),
                      ],
                    ),
                  ),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
