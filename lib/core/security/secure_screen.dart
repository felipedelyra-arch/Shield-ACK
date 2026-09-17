import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';

/// Impede screenshot e gravação de tela nas telas de conteúdo.
///
/// Android: FLAG_SECURE — bloqueia screenshot, gravação e preview no multitarefa.
/// iOS: não existe equivalente. `isCaptureActive` permite DETECTAR gravação e
/// cobrir a tela com um overlay; screenshot estático não é bloqueável.
///
/// Limite honesto: nada disto impede uma câmera apontada para o aparelho.
/// O objetivo é elevar o custo da cópia casual, não impedir pirataria determinada.
class SecureScreen extends StatefulWidget {
  const SecureScreen({required this.child, super.key});
  final Widget child;

  @override
  State<SecureScreen> createState() => _SecureScreenState();
}

class _SecureScreenState extends State<SecureScreen>
    with WidgetsBindingObserver {
  static const _ios = MethodChannel('shieldack/secure_screen');
  bool _captured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enable();
  }

  Future<void> _enable() async {
    if (Platform.isAndroid) {
      await FlutterWindowManagerPlus.addFlags(
          FlutterWindowManagerPlus.FLAG_SECURE);
    } else if (Platform.isIOS) {
      _captured = await _ios.invokeMethod<bool>('isCaptureActive') ?? false;
      if (mounted) setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (Platform.isIOS && state == AppLifecycleState.resumed) _enable();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Remover o flag no dispose é obrigatório: deixá-lo ligado quebra o preview
    // do app no multitarefa e algumas superfícies de vídeo em devices antigos.
    if (Platform.isAndroid) {
      FlutterWindowManagerPlus.clearFlags(FlutterWindowManagerPlus.FLAG_SECURE);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_captured) {
      return const ColoredBox(
        color: Color(0xFF0B0F14),
        child: Center(child: Text('Gravação de tela detectada')),
      );
    }
    return widget.child;
  }
}
