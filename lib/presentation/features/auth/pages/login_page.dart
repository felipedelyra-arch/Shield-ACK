import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../failure_text.dart';
import '../../../theme.dart';
import '../../../widgets/network_field.dart';
import '../../../widgets/trace.dart';

/// Entrada.
///
/// A rede ao fundo é o produto em uma imagem: você é o nó do centro, e cada aula
/// concluída é mais tráfego fechando handshake. Ela encolhe quando o formulário
/// de e-mail abre, para o teclado caber sem esconder nada.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _emailMode = false;
  bool _signUp = false;
  bool _showPassword = false;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _run(Future<Result<Failure, void>> Function() action) async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final r = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    r.fold(
      (f) {
        if (f case InvalidInputFailure(code: 'CANCELED')) return;
        HapticFeedback.heavyImpact();
        _toast(failureText(f));
      },
      // Com Firebase o redirect do router já faz isto; na demo não há redirect.
      (_) => context.go('/'),
    );
  }

  /// Validação local só para poupar uma ida ao servidor. A política real de senha
  /// (tamanho, vazamento) é do Identity Platform.
  void _submitEmail() {
    if (!_email.text.contains('@')) return _toast('Informe um e-mail válido.');
    if (_password.text.length < 8) {
      return _toast('A senha tem pelo menos 8 caracteres.');
    }
    final auth = ref.read(authRepositoryProvider);
    _run(() => _signUp
        ? auth.signUpWithEmail(_email.text, _password.text)
        : auth.signInWithEmail(_email.text, _password.text));
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.read(authRepositoryProvider);
    final motion = reduceMotion(context)
        ? Duration.zero
        : const Duration(milliseconds: 420);
    final height = MediaQuery.sizeOf(context).height;

    return Scaffold(
      body: Stack(
        children: [
          AnimatedPositioned(
            duration: motion,
            curve: Curves.easeOutCubic,
            top: 0,
            left: 0,
            right: 0,
            height: height * (_emailMode ? 0.30 : 0.58),
            child: const _FadedNetwork(),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AnimatedSize(
                        duration: motion,
                        curve: Curves.easeOutCubic,
                        child: SizedBox(
                            height: height * (_emailMode ? 0.16 : 0.36)),
                      ),
                      Text('Shield Ack', style: Face.hero),
                      const SizedBox(height: Gap.sm),
                      Text(
                        'Redes, ataques e defesa em aulas de 10 minutos. '
                        'Cada acerto põe mais um nó da sua rede no ar.',
                        style: Face.body
                            .copyWith(color: Shade.textDim, fontSize: 16),
                      ),
                      const SizedBox(height: Gap.xl),
                      AnimatedSwitcher(
                        duration: motion,
                        switchInCurve: Curves.easeOutCubic,
                        transitionBuilder: (child, a) => FadeTransition(
                          opacity: a,
                          child: SlideTransition(
                            position: Tween(
                                    begin: const Offset(0, 0.08),
                                    end: Offset.zero)
                                .animate(a),
                            child: child,
                          ),
                        ),
                        child: _emailMode
                            ? _emailForm()
                            : _choices(auth.signInWithGoogle),
                      ),
                      const SizedBox(height: Gap.lg),
                      Text(
                        'Ao entrar você aceita a política de privacidade.\n'
                        'Seu e-mail nunca aparece para outros alunos.',
                        textAlign: TextAlign.center,
                        style: Face.meta
                            .copyWith(fontSize: 12, color: Shade.textFaint),
                      ),
                      const SizedBox(height: Gap.md),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _choices(Future<Result<Failure, void>> Function() google) => Column(
        key: const ValueKey('choices'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ActionButton('Continuar com Google',
              leading: const _GoogleMark(),
              tone: Shade.text,
              busy: _busy,
              onPressed: () => _run(google)),
          const SizedBox(height: Gap.sm),
          ActionButton('Entrar com e-mail',
              icon: Icons.alternate_email_rounded,
              outlined: true,
              onPressed:
                  _busy ? null : () => setState(() => _emailMode = true)),
        ],
      );

  Widget _emailForm() => Column(
        key: const ValueKey('email'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Voltar',
                onPressed:
                    _busy ? null : () => setState(() => _emailMode = false),
                icon: const Icon(Icons.arrow_back_rounded),
                color: Shade.textDim,
              ),
              const SizedBox(width: Gap.xs),
              Expanded(
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('Entrar')),
                    ButtonSegment(value: true, label: Text('Criar conta')),
                  ],
                  selected: {_signUp},
                  onSelectionChanged: (s) {
                    HapticFeedback.selectionClick();
                    setState(() => _signUp = s.first);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          AutofillGroup(
            child: Column(
              children: [
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    prefixIcon: Icon(Icons.alternate_email_rounded),
                  ),
                ),
                const SizedBox(height: Gap.sm),
                TextField(
                  controller: _password,
                  obscureText: !_showPassword,
                  textInputAction: TextInputAction.done,
                  autofillHints: [
                    _signUp ? AutofillHints.newPassword : AutofillHints.password
                  ],
                  onSubmitted: (_) => _submitEmail(),
                  decoration: InputDecoration(
                    labelText: 'Senha',
                    helperText: _signUp ? 'Pelo menos 8 caracteres.' : null,
                    prefixIcon: const Icon(Icons.key_rounded),
                    suffixIcon: IconButton(
                      tooltip:
                          _showPassword ? 'Esconder senha' : 'Mostrar senha',
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                      icon: Icon(_showPassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.lg),
          ActionButton(_signUp ? 'Criar conta' : 'Entrar',
              busy: _busy, onPressed: _submitEmail),
        ],
      );
}

/// A rede some no fundo em vez de terminar numa borda reta.
class _FadedNetwork extends StatelessWidget {
  const _FadedNetwork();

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (r) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, Colors.white, Colors.transparent],
        stops: [0, 0.6, 1],
      ).createShader(r),
      child: const NetworkField(),
    );
  }
}

/// "G" em peso de marca. Sem o logotipo oficial como asset, a letra sozinha
/// identifica o provedor sem imitar a marca.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) => Text('G',
      style: Face.title.copyWith(
          fontSize: 22, fontWeight: FontWeight.w800, color: Shade.base));
}
