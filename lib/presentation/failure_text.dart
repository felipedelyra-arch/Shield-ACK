import '../core/error/failure.dart';

/// O que a pessoa lê quando algo falha. Diz o que fazer, nunca o detalhe interno.
String failureText(Failure f) => switch (f) {
      OfflineFailure() => 'Sem conexão. Tente de novo quando a rede voltar.',
      RateLimitedFailure(:final retryAfterSec) =>
        'Muitas tentativas. Tente de novo em $retryAfterSec s.',
      DeniedFailure(code: 'NO_HEARTS') =>
        'Sem vidas agora. Uma volta a cada 30 minutos.',
      DeniedFailure(code: 'PREVIOUS_LESSON_INCOMPLETE' || 'LESSON_LOCKED') =>
        'Conclua a aula anterior primeiro.',
      DeniedFailure(code: 'ACCOUNT_BLOCKED') => 'Esta conta está bloqueada.',
      InvalidInputFailure(code: 'INVALID_CREDENTIALS') =>
        'E-mail ou senha incorretos.',
      InvalidInputFailure(code: 'INVALID_EMAIL') => 'E-mail inválido.',
      InvalidInputFailure(code: 'WEAK_PASSWORD') =>
        'Senha fraca. Use pelo menos 8 caracteres, misturando letras e números.',
      InvalidInputFailure(code: 'EMAIL_IN_USE') =>
        'Este e-mail já tem conta. Use "Entrar".',
      // Recusa vinda da fila chega como DeniedFailure com o código original.
      InvalidInputFailure(code: 'INCOMPLETE_ANSWERS') ||
      DeniedFailure(code: 'INCOMPLETE_ANSWERS') =>
        'Faltou responder alguma questão.',
      IntegrityRejectedFailure() =>
        'Este aparelho não passou na verificação de integridade.',
      SessionRevokedFailure() ||
      UnauthenticatedFailure() =>
        'Sessão encerrada. Entre de novo.',
      _ => 'Algo deu errado. Tente de novo.',
    };
