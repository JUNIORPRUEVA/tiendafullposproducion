import { CallHandler, ExecutionContext, Injectable, NestInterceptor } from '@nestjs/common';
import { Role } from '@prisma/client';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';

function stripCosto(value: any): any {
  if (Array.isArray(value)) return value.map(stripCosto);
  if (value && typeof value === 'object') {
    const { costo, ...rest } = value as any;
    return rest;
  }
  return value;
}

@Injectable()
export class ProductCostInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    const request = context.switchToHttp().getRequest();
    const role: Role | undefined = request.user?.role;
    const canSeeCosto = role === Role.ADMIN || role === Role.ASISTENTE;
    if (canSeeCosto) return next.handle();
    return next.handle().pipe(map((data) => stripCosto(data)));
  }
}

