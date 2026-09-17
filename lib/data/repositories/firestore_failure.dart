import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/error/failure.dart';
import '../../core/error/result.dart';

/// Leitura do Firestore → [Result]. A UI nunca vê [FirebaseException].
Future<Result<Failure, T>> guardFirestore<T>(Future<T> Function() read) async {
  try {
    return Ok(await read());
  } on FirebaseException catch (e) {
    return Err(switch (e.code) {
      // Leitura não tem fila: "offline" aqui é sem cache, não "vai subir depois".
      'unavailable' => const OfflineFailure(queued: false),
      'permission-denied' => DeniedFailure(e.code),
      'not-found' => const NotFoundFailure(),
      _ => UnexpectedFailure('firestore:${e.code}'),
    });
  } catch (e) {
    return Err(UnexpectedFailure(e.toString()));
  }
}
