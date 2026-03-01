import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function safeString(value: unknown): string {
  if (typeof value === 'string') return value;
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

@Catch()
export class GlobalExceptionFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const req = ctx.getRequest<{
      method?: string;
      originalUrl?: string;
      url?: string;
      ip?: string;
    }>();
    const res = ctx.getResponse<{ status: (code: number) => any; json: (body: any) => any }>();

    const method = req?.method ?? 'UNKNOWN';
    const url = req?.originalUrl ?? req?.url ?? 'UNKNOWN';

    const isHttp = exception instanceof HttpException;
    const status = isHttp
      ? exception.getStatus()
      : HttpStatus.INTERNAL_SERVER_ERROR;

    const isProd = (process.env.NODE_ENV ?? '').toLowerCase() === 'production';

    const prismaDetails: Record<string, unknown> | null =
      exception instanceof Prisma.PrismaClientKnownRequestError
        ? {
            kind: 'PrismaClientKnownRequestError',
            code: exception.code,
            meta: exception.meta,
            clientVersion: exception.clientVersion,
          }
        : exception instanceof Prisma.PrismaClientUnknownRequestError
          ? {
              kind: 'PrismaClientUnknownRequestError',
              clientVersion: exception.clientVersion,
            }
          : exception instanceof Prisma.PrismaClientValidationError
            ? {
                kind: 'PrismaClientValidationError',
                clientVersion: exception.clientVersion,
              }
            : exception instanceof Prisma.PrismaClientInitializationError
              ? {
                  kind: 'PrismaClientInitializationError',
                  errorCode: exception.errorCode,
                  clientVersion: exception.clientVersion,
                }
              : exception instanceof Prisma.PrismaClientRustPanicError
                ? {
                    kind: 'PrismaClientRustPanicError',
                    clientVersion: exception.clientVersion,
                  }
                : null;

    const message = isHttp
      ? safeString(exception.getResponse())
      : exception instanceof Error
        ? exception.message
        : safeString(exception);

    // Always log full details to stderr.
    const stack = exception instanceof Error ? exception.stack : undefined;
    // eslint-disable-next-line no-console
    console.error('[error]', {
      method,
      url,
      status,
      message,
      prisma: prismaDetails,
      stack,
    });

    // Safe error response for clients.
    const responseBody: Record<string, unknown> = {
      statusCode: status,
      path: url,
      method,
      timestamp: new Date().toISOString(),
      message: isHttp ? message : 'Error interno del servidor',
    };

    if (!isProd) {
      if (stack) responseBody.stack = stack;
      if (prismaDetails) responseBody.prisma = prismaDetails;
      if (isObject(exception)) responseBody.debug = exception;
    }

    res.status(status).json(responseBody);
  }
}
