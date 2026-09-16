import 'package:local_auth/local_auth.dart';

/// Protege telas críticas (perfil, exportação de dados, exclusão de conta).
///
/// `biometricOnly: false` é deliberado: o fallback é a credencial do DISPOSITIVO
/// (PIN/padrão/senha do SO), não um PIN próprio do app.
/// Um PIN caseiro significaria nós guardando e comparando um segredo de 4–6 dígitos
/// — pior que o Keystore em todos os aspectos. Ver docs/00-CORRECOES.md C10.
class BiometricGate {
  BiometricGate({LocalAuthentication? auth}) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  /// Device sem biometria E sem credencial configurada: [canAuthenticate] é false.
  /// Neste caso NÃO bloqueamos o acesso — bloquear tornaria a conta inacessível
  /// num aparelho sem tela de bloqueio. Registramos e seguimos.
  Future<bool> get isAvailable async =>
      await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;

  Future<BiometricOutcome> require(String reason) async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return BiometricOutcome.unavailable;

      final ok = await _auth.authenticate(
        localizedReason: reason,
        // local_auth 3 achatou os parâmetros: `stickyAuth` virou
        // `persistAcrossBackgrounding` e `useErrorDialogs` deixou de existir.
        biometricOnly: false,
        persistAcrossBackgrounding: true, // sobrevive ao app ir para background no prompt
        sensitiveTransaction: true,
      );
      return ok ? BiometricOutcome.granted : BiometricOutcome.denied;
    } on Exception {
      return BiometricOutcome.unavailable;
    }
  }
}

enum BiometricOutcome { granted, denied, unavailable }
