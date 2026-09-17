import 'package:workmanager/workmanager.dart';

import '../../../core/di/providers.dart';
import '../../../core/firebase/firebase_bootstrap.dart';
import '../../../main.dart' show emulatorHost, isProd;

const outboxTaskName = 'shieldack.outbox.drain';

/// Drenagem da fila com o app ENCERRADO.
///
/// Sem isto, a promessa "o usuário nunca perde a sequência em que parou" só vale
/// enquanto o app estiver aberto: o usuário responde o quiz no metrô sem rede,
/// mata o app, e o XP nunca sobe.
///
/// Android: WorkManager, constraint de rede conectada, backoff do próprio SO.
/// iOS: BGTaskScheduler — o SO decide QUANDO rodar e pode nunca rodar se o app
/// for pouco usado. Por isso a drenagem no `resume` do app continua sendo o
/// caminho principal; o background é reforço, não garantia. Limitação do iOS,
/// não da implementação.
@pragma('vm:entry-point')
void outboxCallbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    if (task != outboxTaskName) return true;
    try {
      // Mesmo bootstrap do app: sem App Check ativo, toda Callable em prod responde
      // APP_CHECK_REQUIRED e o item morre depois de 8 tentativas.
      await FirebaseBootstrap.init(isProd: isProd, emulatorHost: emulatorHost);
      final container = await buildHeadlessContainer();
      await container.read(outboxProvider).drain();
      container.dispose();
      return true;
    } catch (_) {
      // Devolver false pede retry ao SO, que aplica o próprio backoff.
      return false;
    }
  });
}

Future<void> registerOutboxWorker() async {
  await Workmanager().initialize(outboxCallbackDispatcher);
  await Workmanager().registerPeriodicTask(
    outboxTaskName,
    outboxTaskName,
    frequency: const Duration(minutes: 15), // mínimo que o Android aceita
    constraints: Constraints(networkType: NetworkType.connected),
    // Trabalho periódico tem enum próprio; `keep` evita recriar a tarefa a cada boot.
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    backoffPolicy: BackoffPolicy.exponential,
  );
}
