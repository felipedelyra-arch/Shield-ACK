import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../data/datasources/local/app_database.dart';
import 'integrity_service.dart';
import 'security_service.dart';

/// Ciclo de vida da sessão e resposta a comprometimento.
///
/// Concentra o WIPE num lugar só. Espalhar limpeza por vários pontos é como se
/// perde uma superfície: alguém adiciona um cache novo e esquece de limpar.
class SessionGuard {
  SessionGuard({
    required FirebaseAuth auth,
    required SecurityService security,
    required AppDatabase db,
    required IntegrityService integrity,
    required Future<void> Function() clearFcmToken,
    required void Function() onForcedLogout,
  })  : _auth = auth,
        _security = security,
        _db = db,
        _integrity = integrity,
        _clearFcmToken = clearFcmToken,
        _onForcedLogout = onForcedLogout;

  final FirebaseAuth _auth;
  final SecurityService _security;
  final AppDatabase _db;
  final IntegrityService _integrity;
  final Future<void> Function() _clearFcmToken;
  final void Function() _onForcedLogout;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<IntegrityLevel>? _integritySub;

  void start() {
    // `idTokenChanges` emite null quando o refresh token é revogado no servidor
    // (revokeRefreshTokens). É assim que o logout global chega ao dispositivo.
    _authSub = _auth.idTokenChanges().listen((user) async {
      if (user == null) return;
      try {
        // force refresh: valida contra o servidor. Sem `true`, um token revogado
        // continua sendo aceito localmente até expirar (até 1h).
        await user.getIdToken(true);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-token-expired' || e.code == 'user-disabled') {
          await forceLogout('id-token-revoked');
        }
      }
    });

    _integritySub = _integrity.level.listen((level) async {
      if (level == IntegrityLevel.activeAttack) {
        await forceLogout('active_attack');
      }
    });
  }

  /// Wipe total. Chamado em: logout do usuário, token revogado, ataque ativo.
  ///
  /// Ordem deliberada: primeiro o que depende de rede (FCM), depois o local.
  /// Se a rede falhar no meio, o dado local ainda é apagado.
  Future<void> forceLogout(String reason) async {
    await _clearFcmToken().catchError((_) {});

    // terminate() antes de clearPersistence(): o SDK recusa limpar com listeners ativos.
    await FirebaseFirestore.instance.terminate().catchError((_) {});
    await FirebaseFirestore.instance.clearPersistence().catchError((_) {});

    await _db.wipe();
    await _security.wipeKeys();
    await _auth.signOut().catchError((_) {});

    _onForcedLogout();
  }

  Future<void> dispose() async {
    await _authSub?.cancel();
    await _integritySub?.cancel();
  }
}
