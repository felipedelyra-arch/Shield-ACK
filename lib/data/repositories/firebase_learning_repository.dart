import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/error/failure.dart';
import '../../core/error/result.dart';
import '../../core/firebase/functions_client.dart';
import '../../domain/entities/learning.dart';
import '../../domain/repositories/learning_repository.dart';
import '../datasources/local/outbox.dart';

class FirebaseLearningRepository implements LearningRepository {
  FirebaseLearningRepository({
    required FirebaseFirestore db,
    required FunctionsClient functions,
    required Outbox outbox,
    required String catalogVersion,
  })  : _db = db,
        _functions = functions,
        _outbox = outbox,
        _catalogVersion = catalogVersion;

  final FirebaseFirestore _db;
  final FunctionsClient _functions;
  final Outbox _outbox;
  final String _catalogVersion;

  @override
  Stream<Profile> watchProfile(String uid) async* {
    var asked = false;
    await for (final s in _db.doc('users/$uid').snapshots()) {
      final m = s.data();
      if (m != null) {
        yield _profile(m);
      } else if (!asked && !s.metadata.isFromCache) {
        // O perfil nasce no servidor (Rules negam create). A chamada é idempotente e
        // cobre tanto o primeiro login quanto um bootstrap que falhou sem rede.
        asked = true;
        unawaited(_functions.call('bootstrapProfile', const {}));
      }
    }
  }

  Profile _profile(Map<String, dynamic> m) => Profile(
        displayName: m['displayName'] as String? ?? '',
        xp: (m['xp'] as num?)?.toInt() ?? 0,
        level: (m['level'] as num?)?.toInt() ?? 1,
        streakDays: (m['streakDays'] as num?)?.toInt() ?? 0,
        hearts: displayHearts(
          (m['hearts'] as num?)?.toInt() ?? 5,
          (m['heartsUpdatedAt'] as Timestamp?)?.toDate(),
          DateTime.now(),
        ),
        friendCode: m['friendCode'] as String? ?? '',
      );

  /// Catálogo: 1 leitura do documento agregado (sem listener — publicação nova chega
  /// pelo Remote Config). Progresso: listener, para a trilha andar quando o quiz passa.
  @override
  Stream<List<Track>> watchTracks(String uid) async* {
    final catalog = await _db.doc('catalog/$_catalogVersion').get();
    final tracks = (catalog.data()?['tracks'] as List? ?? const []).cast<Map>();

    // ponytail: limit(500) cobre o catálogo inteiro hoje; paginar por trilha quando passar disso.
    yield* _db
        .collection('users/$uid/progress')
        .limit(500)
        .snapshots()
        .map((snap) {
      final byId = {for (final d in snap.docs) d.id: _progress(d.data())};
      return [for (final t in tracks) _track(t, byId)];
    });
  }

  LessonProgress _progress(Map<String, dynamic> m) => LessonProgress(
        completed: m['status'] == 'completed',
        attempts: (m['attempts'] as num?)?.toInt() ?? 0,
        lastPositionSec: (m['lastPositionSec'] as num?)?.toInt() ?? 0,
      );

  Track _track(Map t, Map<String, LessonProgress> byId) {
    final lessons = <Lesson>[];
    for (final module in (t['modules'] as List).cast<Map>()) {
      final raw = (module['lessons'] as List).cast<Map>();
      final statuses = resolveModule([for (final l in raw) byId[l['id']]]);
      for (var i = 0; i < raw.length; i++) {
        final id = raw[i]['id'] as String;
        lessons.add(Lesson(
          id: id,
          title: raw[i]['title'] as String,
          durationSec: (raw[i]['durationSec'] as num).toInt(),
          xpReward: (raw[i]['xpReward'] as num).toInt(),
          status: statuses[i],
          resumeAtSec: byId[id]?.lastPositionSec ?? 0,
        ));
      }
    }
    return Track(
      id: t['id'] as String,
      title: t['title'] as String,
      blurb: t['blurb'] as String? ?? '',
      lessons: lessons,
    );
  }

  @override
  Future<Result<Failure, int>> startLesson(String lessonId) async =>
      (await _functions.call('startLesson', {'lessonId': lessonId}))
          .map((d) => (d['resumeAtSec'] as num?)?.toInt() ?? 0);

  @override
  Future<void> reportWatch(String lessonId, int positionSec, int watchedSec) =>
      _outbox.enqueue('syncWatchProgress', {
        'items': [
          {
            'lessonId': lessonId,
            'positionSec': positionSec.clamp(0, 86400),
            'watchedDeltaSec': watchedSec.clamp(0, 3600),
            'clientTs': DateTime.now().millisecondsSinceEpoch,
          }
        ],
      });
}
