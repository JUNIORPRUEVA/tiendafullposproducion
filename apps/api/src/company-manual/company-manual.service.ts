import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { CompanyManualAudience, CompanyManualEntryKind, Prisma, Role } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CompanyManualQueryDto } from './dto/company-manual-query.dto';
import { UpsertCompanyManualDto } from './dto/upsert-company-manual.dto';

type CurrentUser = { id: string; role: Role };

@Injectable()
export class CompanyManualService {
  constructor(private readonly prisma: PrismaService) {}

  async resolveCompanyOwnerId(fallbackUserId: string) {
    const admin = await this.prisma.user.findFirst({
      where: { role: Role.ADMIN },
      orderBy: { createdAt: 'asc' },
      select: { id: true },
    });
    return admin?.id ?? fallbackUserId;
  }

  async list(user: CurrentUser, query: CompanyManualQueryDto) {
    const ownerId = await this.resolveCompanyOwnerId(user.id);
    await this.ensureStarterEntries(ownerId, user.id);
    const where = this.buildWhere(ownerId, user, query);
    const items = await this.prisma.companyManualEntry.findMany({
      where,
      orderBy: [{ sortOrder: 'asc' }, { updatedAt: 'desc' }, { title: 'asc' }],
    });
    return { items };
  }

  async findOne(user: CurrentUser, id: string) {
    const ownerId = await this.resolveCompanyOwnerId(user.id);
    const item = await this.prisma.companyManualEntry.findFirst({
      where: {
        id,
        ...this.buildWhere(ownerId, user, { includeHidden: false }),
      },
    });

    if (!item) {
      throw new NotFoundException('La entrada del manual no existe');
    }

    return item;
  }

  async summary(user: CurrentUser, seenAt?: string) {
    const ownerId = await this.resolveCompanyOwnerId(user.id);
    await this.ensureStarterEntries(ownerId, user.id);
    const where = this.buildWhere(ownerId, user, { includeHidden: false });

    const [count, latest] = await this.prisma.$transaction([
      this.prisma.companyManualEntry.count({ where }),
      this.prisma.companyManualEntry.aggregate({
        where,
        _max: { updatedAt: true },
      }),
    ]);

    let unreadCount = count;
    const latestUpdatedAt = latest._max.updatedAt ?? null;
    if (seenAt?.trim()) {
      const seenDate = new Date(seenAt);
      if (!Number.isNaN(seenDate.getTime())) {
        unreadCount = await this.prisma.companyManualEntry.count({
          where: { ...where, updatedAt: { gt: seenDate } },
        });
      }
    }

    return {
      totalCount: count,
      unreadCount,
      latestUpdatedAt: latestUpdatedAt?.toISOString() ?? null,
    };
  }

  async upsert(user: CurrentUser, dto: UpsertCompanyManualDto) {
    const ownerId = await this.resolveCompanyOwnerId(user.id);
    const title = dto.title.trim();
    const content = dto.content.trim();
    const summary = dto.summary?.trim();
    const moduleKey = dto.moduleKey?.trim().toLowerCase();
    const targetRoles = this.normalizeTargetRoles(dto.audience, dto.targetRoles);

    if (!title) throw new BadRequestException('El título es obligatorio');
    if (!content) throw new BadRequestException('El contenido es obligatorio');

    const data = {
      ownerId,
      title,
      summary: summary && summary.length > 0 ? summary : null,
      content,
      kind: dto.kind,
      audience: dto.audience,
      targetRoles,
      moduleKey: moduleKey && moduleKey.length > 0 ? moduleKey : null,
      published: dto.published ?? true,
      sortOrder: dto.sortOrder ?? 0,
      updatedByUserId: user.id,
    };

    if (dto.id) {
      const existing = await this.prisma.companyManualEntry.findFirst({
        where: { id: dto.id, ownerId },
        select: { id: true, createdByUserId: true },
      });
      if (!existing) {
        throw new NotFoundException('La entrada del manual no existe');
      }

      return this.prisma.companyManualEntry.update({
        where: { id: dto.id },
        data: { ...data, createdByUserId: existing.createdByUserId },
      });
    }

    return this.prisma.companyManualEntry.create({
      data: { ...data, createdByUserId: user.id },
    });
  }

  async remove(user: CurrentUser, id: string) {
    const ownerId = await this.resolveCompanyOwnerId(user.id);
    const existing = await this.prisma.companyManualEntry.findFirst({
      where: { id, ownerId },
      select: { id: true },
    });
    if (!existing) {
      throw new NotFoundException('La entrada del manual no existe');
    }

    await this.prisma.companyManualEntry.delete({ where: { id } });
    return { ok: true };
  }

  private async ensureStarterEntries(ownerId: string, actorUserId: string) {
    const count = await this.prisma.companyManualEntry.count({ where: { ownerId } });
    if (count > 0) return;

    const entries: Array<Prisma.CompanyManualEntryCreateInput> = [
      {
        ownerId,
        createdByUserId: actorUserId,
        updatedByUserId: actorUserId,
        title: 'Atencion y registro correcto del cliente',
        summary: 'Toda gestion debe iniciar con datos completos y trazables del cliente.',
        content: `1. Confirmar nombre, telefono y necesidad principal antes de crear cualquier registro.
2. Evitar duplicados; si el cliente ya existe, actualizar su ficha en lugar de crear otra.
3. Registrar observaciones claras y verificables para que operaciones, ventas y soporte trabajen con la misma informacion.
4. No prometer tiempos, precios o garantias fuera de lo documentado en el sistema.`,
        kind: CompanyManualEntryKind.GENERAL_RULE,
        audience: CompanyManualAudience.GENERAL,
        targetRoles: [],
        moduleKey: 'clientes',
        published: true,
        sortOrder: 1,
      },
      {
        ownerId,
        createdByUserId: actorUserId,
        updatedByUserId: actorUserId,
        title: 'Politica base de cotizaciones y precios',
        summary: 'Los precios y descuentos deben sustentarse en la cotizacion registrada.',
        content: `1. Toda oferta debe salir desde el modulo de cotizaciones o quedar respaldada en el sistema.
2. No se deben modificar precios finales sin dejar justificacion comercial.
3. Antes de confirmar una venta, validar monto, alcance y condiciones con el cliente.
4. Si existe una excepcion comercial, debe quedar observacion escrita y responsable identificado.`,
        kind: CompanyManualEntryKind.PRICE_RULE,
        audience: CompanyManualAudience.GENERAL,
        targetRoles: [],
        moduleKey: 'cotizaciones',
        published: true,
        sortOrder: 2,
      },
      {
        ownerId,
        createdByUserId: actorUserId,
        updatedByUserId: actorUserId,
        title: 'Politica de garantia y evidencia',
        summary: 'Toda gestion de garantia requiere evidencia clara, fecha y condicion de entrega.',
        content: `1. La garantia debe registrarse con descripcion del caso, evidencia y fecha de recepcion.
2. El tecnico o responsable debe indicar diagnostico preliminar y estado actual del equipo o servicio.
3. No se aprueban garantias sin trazabilidad suficiente ni sin validacion del historial correspondiente.
4. El cliente debe recibir una explicacion clara del alcance de la garantia y sus limitaciones.`,
        kind: CompanyManualEntryKind.WARRANTY_POLICY,
        audience: CompanyManualAudience.GENERAL,
        targetRoles: [],
        moduleKey: 'operaciones',
        published: true,
        sortOrder: 3,
      },
      {
        ownerId,
        createdByUserId: actorUserId,
        updatedByUserId: actorUserId,
        title: 'Regla de servicio para seguimiento operativo',
        summary: 'Cada proceso debe reflejar su estado real en el sistema para evitar errores de coordinacion.',
        content: `1. Actualizar la fase del servicio inmediatamente cuando cambie la situacion operativa.
2. Registrar notas utiles, pendientes y responsables visibles para el siguiente usuario.
3. No cerrar un servicio sin confirmar entrega, conformidad o siguiente accion definida.
4. Toda incidencia que afecte tiempo, costo o alcance debe quedar documentada.`,
        kind: CompanyManualEntryKind.SERVICE_RULE,
        audience: CompanyManualAudience.GENERAL,
        targetRoles: [],
        moduleKey: 'operaciones',
        published: true,
        sortOrder: 4,
      },
      {
        ownerId,
        createdByUserId: actorUserId,
        updatedByUserId: actorUserId,
        title: 'Responsabilidad al actualizar estados y datos',
        summary: 'Quien modifica un registro es responsable de la exactitud y completitud del cambio.',
        content: `1. Antes de guardar cambios, revisar que el cliente, servicio o venta correcto este seleccionado.
2. Evitar dejar campos claves en blanco cuando el proceso ya dispone de esa informacion.
3. Si un cambio impacta otra area, dejar nota visible para mantener continuidad operativa.
4. No usar datos temporales o no verificados como informacion definitiva.`,
        kind: CompanyManualEntryKind.RESPONSIBILITY,
        audience: CompanyManualAudience.GENERAL,
        targetRoles: [],
        moduleKey: 'general',
        published: true,
        sortOrder: 5,
      },
      {
        ownerId,
        createdByUserId: actorUserId,
        updatedByUserId: actorUserId,
        title: 'Guia rapida de uso de modulos principales',
        summary: 'Clientes, cotizaciones y operaciones deben usarse como una cadena continua de trabajo.',
        content: `1. Registrar o validar el cliente antes de iniciar una cotizacion o servicio.
2. Usar cotizaciones para dejar claro el alcance comercial antes de ejecutar.
3. Mover el seguimiento a operaciones cuando el proceso requiera ejecucion o control tecnico.
4. Mantener consistencia entre lo vendido, lo ejecutado y lo entregado.`,
        kind: CompanyManualEntryKind.MODULE_GUIDE,
        audience: CompanyManualAudience.GENERAL,
        targetRoles: [],
        moduleKey: 'general',
        published: true,
        sortOrder: 6,
      },
    ];

    await this.prisma.$transaction(
      entries.map((entry) => this.prisma.companyManualEntry.create({ data: entry })),
    );
  }

  private normalizeTargetRoles(audience: CompanyManualAudience, targetRoles?: Role[]) {
    if (audience === CompanyManualAudience.GENERAL) return [];
    const uniqueRoles = Array.from(new Set((targetRoles ?? []).filter(Boolean)));
    if (uniqueRoles.length == 0) {
      throw new BadRequestException(
        'Debes indicar al menos un rol cuando la entrada es específica por rol',
      );
    }
    return uniqueRoles;
  }

  private buildWhere(
    ownerId: string,
    user: CurrentUser,
    query: Partial<CompanyManualQueryDto>,
  ): Prisma.CompanyManualEntryWhereInput {
    const where: Prisma.CompanyManualEntryWhereInput = { ownerId };

    if (query.kind) where.kind = query.kind as CompanyManualEntryKind;
    if (query.audience) where.audience = query.audience as CompanyManualAudience;
    if (query.moduleKey?.trim()) {
      where.moduleKey = query.moduleKey.trim().toLowerCase();
    }
    if (query.role) {
      where.targetRoles = { has: query.role as Role };
    }

    if (user.role !== Role.ADMIN || query.includeHidden !== true) {
      where.published = true;
    }

    if (user.role !== Role.ADMIN) {
      where.OR = [
        { audience: CompanyManualAudience.GENERAL },
        {
          audience: CompanyManualAudience.ROLE_SPECIFIC,
          targetRoles: { has: user.role },
        },
      ];
    }

    return where;
  }
}