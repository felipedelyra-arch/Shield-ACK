import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../security/pinning_service.dart';

/// Cliente HTTP para APIs PRÓPRIAS e CDN de vídeo.
///
/// Os SDKs do Firebase NÃO passam por aqui — usam a própria pilha de rede.
/// Por isso o pinning configurado neste cliente cobre apenas domínios próprios
/// (ver docs/05-seguranca-mobile.md §5.2).
Dio buildDioClient({required PinningService pinning, required String baseUrl}) {
  final dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
    sendTimeout: const Duration(seconds: 20),
    headers: {'Accept': 'application/json'},
  ));

  pinning.apply(dio);

  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    },
    onError: (e, handler) async {
      // Retry apenas em método idempotente. Repetir um POST cegamente é como se
      // duplica uma cobrança — aqui, uma submissão.
      final idempotent =
          const {'GET', 'HEAD', 'PUT'}.contains(e.requestOptions.method);
      final retriable = e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          (e.response?.statusCode ?? 0) >= 500;

      if (idempotent &&
          retriable &&
          (e.requestOptions.extra['retried'] ?? 0) < 2) {
        e.requestOptions.extra['retried'] =
            (e.requestOptions.extra['retried'] ?? 0) + 1;
        try {
          return handler.resolve(await dio.fetch(e.requestOptions));
        } catch (_) {/* cai no erro original */}
      }
      handler.next(e);
    },
  ));

  return dio;
}
