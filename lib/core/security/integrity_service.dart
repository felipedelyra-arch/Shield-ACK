import 'dart:async';
import 'dart:convert';

import 'package:freerasp/freerasp.dart';

import 'security_service.dart';

/// Severidade do sinal de integridade, do mais tolerável ao intolerável.
enum IntegrityLevel {
  /// Nada detectado.
  clean,

  /// Emulador ou debugger. Comum em QA e em usuários curiosos do próprio app.
  observed,

  /// Root/jailbreak. O device é hostil, mas o usuário pode ser legítimo.
  compromisedDevice,

  /// Hooking ativo (Frida/Xposed) ou binário repackaged/assinatura errada.
  /// Isto não acontece por acidente.
  activeAttack,
}

/// Política GRADUADA — não binária.
///
/// Por que não bloquear tudo no primeiro sinal de root:
///  - detecção local é contornável por definição (o atacante controla o processo
///    que faz a checagem), então bloquear não impede o atacante — só pune o usuário;
///  - uma parcela real de usuários de um app de SEGURANÇA tem device rooteado
///    de propósito. Expulsá-los destrói o produto para o público-alvo;
///  - o que efetivamente barra cliente não autêntico é o **App Check** no backend
///    (Play Integrity / App Attest), que o atacante não controla.
///
/// Portanto a detecção local serve para: telemetria, degradação de funcionalidade
/// sensível, e bloqueio apenas no caso de ataque ativo.
///
/// | Nível              | Ação                                                         |
/// |--------------------|--------------------------------------------------------------|
/// | clean              | nada                                                          |
/// | observed           | auditLogs; sem mudança de UX                                 |
/// | compromisedDevice  | desliga download offline e duelo ranqueado; conteúdo segue   |
/// | activeAttack       | wipe local + logout + revogação de sessão                    |
class IntegrityService {
  IntegrityService(this._security);

  final SecurityService _security;

  final _controller = StreamController<IntegrityLevel>.broadcast();
  Stream<IntegrityLevel> get level => _controller.stream;

  IntegrityLevel _current = IntegrityLevel.clean;
  IntegrityLevel get current => _current;

  /// Callbacks que precisam vir de fora para não acoplar segurança a auth/rede.
  late final Future<void> Function(String reason) onActiveAttack;
  late final void Function(String threat, String severity) onTelemetry;

  Future<void> start({
    required String androidPackageName,
    required String androidSigningHash,
    required String iosBundleId,
    required String iosTeamId,
    required String watcherMail,
  }) async {
    final config = TalsecConfig(
      androidConfig: AndroidConfig(
        packageName: androidPackageName,
        // Hash da assinatura: é o que detecta repackaging. Vem do build, não hardcoded
        // à mão — ver scripts/signing_hash.sh.
        signingCertHashes: [androidSigningHash],
      ),
      iosConfig: IOSConfig(bundleIds: [iosBundleId], teamId: iosTeamId),
      watcherMail: watcherMail,
      isProd: true,
    );

    Talsec.instance.attachListener(
      ThreatCallback(
        onPrivilegedAccess: () => _raise(IntegrityLevel.compromisedDevice, 'root_jailbreak'),
        onDebug: () => _raise(IntegrityLevel.observed, 'debugger'),
        onSimulator: () => _raise(IntegrityLevel.observed, 'simulator'),
        onAppIntegrity: () => _raise(IntegrityLevel.activeAttack, 'app_integrity'),
        onHooks: () => _raise(IntegrityLevel.activeAttack, 'hooking'),
        onSecureHardwareNotAvailable: () => _raise(IntegrityLevel.observed, 'no_secure_hw'),
        onUnofficialStore: () => _raise(IntegrityLevel.compromisedDevice, 'unofficial_store'),
        onDeviceBinding: () => _raise(IntegrityLevel.compromisedDevice, 'device_binding'),
        onObfuscationIssues: () => _raise(IntegrityLevel.observed, 'obfuscation'),
        onPasscode: () => _raise(IntegrityLevel.observed, 'no_passcode'),
      ),
    );

    await Talsec.instance.start(config);
  }

  void _raise(IntegrityLevel level, String threat) {
    onTelemetry(threat, level.name);

    if (level.index <= _current.index) return;
    _current = level;
    _controller.add(level);

    unawaited(_security.saveIntegrityState(
      jsonEncode({'level': level.name, 'threat': threat, 'at': DateTime.now().toIso8601String()}),
    ));

    if (level == IntegrityLevel.activeAttack) {
      unawaited(onActiveAttack(threat));
    }
  }

  /// Consultado pelas features para degradar funcionalidade sensível.
  bool get allowsOfflineDownload => _current.index < IntegrityLevel.compromisedDevice.index;
  bool get allowsRankedDuel => _current.index < IntegrityLevel.compromisedDevice.index;

  Future<void> dispose() => _controller.close();
}
