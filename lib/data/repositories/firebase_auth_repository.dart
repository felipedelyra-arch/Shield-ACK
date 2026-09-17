import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/error/failure.dart';
import '../../core/error/result.dart';
import '../../domain/repositories/learning_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(
    this._auth, {
    required Future<void> Function() wipeSession,
    String? googleServerClientId,
  })  : _wipeSession = wipeSession,
        _googleServerClientId = googleServerClientId;

  final FirebaseAuth _auth;
  final Future<void> Function() _wipeSession;
  final String? _googleServerClientId;
  Future<void>? _googleReady;

  @override
  Stream<String?> watchUid() => _auth.authStateChanges().map((u) => u?.uid);

  @override
  Future<Result<Failure, void>> signInWithGoogle() => _guard(() async {
        final google = GoogleSignIn.instance;
        // initialize só pode rodar uma vez por processo.
        await (_googleReady ??=
            google.initialize(serverClientId: _googleServerClientId));
        final account = await google.authenticate();
        final idToken = account.authentication.idToken;
        if (idToken == null) throw StateError('google_sem_id_token');
        await _auth.signInWithCredential(
            GoogleAuthProvider.credential(idToken: idToken));
      });

  @override
  Future<Result<Failure, void>> signInWithEmail(
          String email, String password) =>
      _guard(() => _auth.signInWithEmailAndPassword(
          email: email.trim(), password: password));

  @override
  Future<Result<Failure, void>> signUpWithEmail(
          String email, String password) =>
      _guard(() async {
        final cred = await _auth.createUserWithEmailAndPassword(
            email: email.trim(), password: password);
        // Verificação libera amigos, duelo e ranking; aprender não depende dela.
        await cred.user?.sendEmailVerification().catchError((_) {});
      });

  /// Sair é wipe total (SessionGuard), não só `signOut`.
  @override
  Future<void> signOut() => _wipeSession();

  Future<Result<Failure, void>> _guard(Future<void> Function() action) async {
    try {
      await action();
      return const Ok(null);
    } on GoogleSignInException catch (e) {
      return Err(e.code == GoogleSignInExceptionCode.canceled
          ? const InvalidInputFailure('CANCELED')
          : UnexpectedFailure('google:${e.code.name}'));
    } on FirebaseAuthException catch (e) {
      return Err(switch (e.code) {
        // Credencial errada e usuário inexistente dão a MESMA resposta: anti-enumeração.
        'invalid-credential' ||
        'wrong-password' ||
        'user-not-found' =>
          const InvalidInputFailure('INVALID_CREDENTIALS'),
        'invalid-email' => const InvalidInputFailure('INVALID_EMAIL'),
        'weak-password' ||
        'password-does-not-meet-requirements' =>
          const InvalidInputFailure('WEAK_PASSWORD'),
        'email-already-in-use' => const InvalidInputFailure('EMAIL_IN_USE'),
        'user-disabled' => const DeniedFailure('ACCOUNT_BLOCKED'),
        'too-many-requests' => const RateLimitedFailure(60),
        'network-request-failed' => const OfflineFailure(queued: false),
        _ => UnexpectedFailure('auth:${e.code}'),
      });
    } catch (e) {
      return Err(UnexpectedFailure(e.toString()));
    }
  }
}
