import { onCall, CallableRequest, CallableOptions } from 'firebase-functions/v2/https';
import { z, ZodType } from 'zod';
import { Err } from './errors';
import { enforceRateLimit, Limit } from './rateLimit';
import { isProd } from './init';

export interface Ctx {
  uid: string;
  emailVerified: boolean;
  role: string;
}

interface GuardOpts<S extends ZodType> {
  schema: S;
  /** Exige e-mail verificado. Usar SOMENTE em superfície social. Ver docs/00-CORRECOES.md C8. */
  requireVerified?: boolean;
  /** Papel mínimo exigido via custom claim. */
  requireRole?: 'teacher' | 'admin';
  limit?: Limit;
  /** Nome usado na chave de rate limit e nos logs. */
  action: string;
  options?: CallableOptions;
}

/**
 * Wrapper único de toda Callable. Nenhuma function é exportada sem passar por aqui.
 *
 * Ordem das checagens é deliberada — o mais barato e mais restritivo primeiro,
 * para que um atacante gaste o mínimo do nosso orçamento:
 *   1. App Check   (barra cliente não autêntico antes de qualquer I/O)
 *   2. Auth        (sem leitura de banco)
 *   3. Claims      (já está no token, custo zero)
 *   4. Schema      (CPU local, sem I/O)
 *   5. Rate limit  (1 transação — só depois que o payload já é válido)
 *   6. Handler
 */
export function guarded<S extends ZodType, R>(
  opts: GuardOpts<S>,
  handler: (data: z.infer<S>, ctx: Ctx, req: CallableRequest) => Promise<R>,
) {
  return onCall(
    {
      // enforceAppCheck rejeita a requisição ANTES do handler rodar.
      // Em dev fica desligado para permitir emulador e testes de integração.
      enforceAppCheck: isProd,
      consumeAppCheckToken: false, // replay protection exige token de uso único; ver docs/07-riscos.md R4
      cors: false,                 // Callable não é chamada de browser neste produto
      ...opts.options,
    },
    async (req) => {
      if (isProd && req.app === undefined) throw Err.appCheck();
      if (!req.auth) throw Err.unauthenticated();

      const token = req.auth.token;
      const ctx: Ctx = {
        uid: req.auth.uid,
        emailVerified: token.email_verified === true,
        role: (token.role as string) ?? 'student',
      };

      if (opts.requireVerified && !ctx.emailVerified) throw Err.emailNotVerified();

      if (opts.requireRole) {
        const ok = opts.requireRole === 'admin'
          ? ctx.role === 'admin'
          : ctx.role === 'admin' || ctx.role === 'teacher';
        if (!ok) throw Err.locked('INSUFFICIENT_ROLE');
      }

      const parsed = opts.schema.safeParse(req.data);
      if (!parsed.success) {
        // Nunca devolver o erro do zod cru: revela o formato interno esperado.
        const first = parsed.error.issues[0];
        throw Err.invalidArg(`INVALID_${(first?.path.join('.') ?? 'PAYLOAD').toUpperCase()}`);
      }

      try {
        if (opts.limit) await enforceRateLimit(ctx.uid, opts.action, opts.limit);
        return await handler(parsed.data, ctx, req);
      } catch (e) {
        // ABORTED (gRPC 10) cru do Firestore = transação perdeu a disputa após os retries
        // do SDK. É transitório; sem isto vira INTERNAL e o cliente descarta o item.
        if ((e as { code?: unknown }).code === 10) throw Err.contention();
        throw e;
      }
    },
  );
}
