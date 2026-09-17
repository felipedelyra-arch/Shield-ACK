import '../../core/error/failure.dart';
import '../../core/error/result.dart';
import '../entities/learning.dart';

/// Trilha, perfil e aula. Implementações: Firebase (data/) e demo (lib/demo/).
abstract interface class LearningRepository {
  Stream<Profile> watchProfile(String uid);

  Stream<List<Track>> watchTracks(String uid);

  /// Autoriza a aula no servidor e devolve de onde retomar, em segundos.
  Future<Result<Failure, int>> startLesson(String lessonId);

  /// Posição assistida. Vai pela fila: perder a rede não perde a posição.
  Future<void> reportWatch(String lessonId, int positionSec, int watchedSec);
}

abstract interface class AuthRepository {
  /// uid da sessão atual, ou null deslogado.
  Stream<String?> watchUid();

  Future<Result<Failure, void>> signInWithGoogle();

  Future<Result<Failure, void>> signInWithEmail(String email, String password);

  Future<Result<Failure, void>> signUpWithEmail(String email, String password);

  Future<void> signOut();
}
