import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { CompanyManualAudience, CompanyManualEntryKind, Prisma, Role } from '@prisma/client';
import { createHash } from 'node:crypto';
import { PrismaService } from '../prisma/prisma.service';
import { CompanyManualQueryDto } from './dto/company-manual-query.dto';
import { UpsertCompanyManualDto } from './dto/upsert-company-manual.dto';

type CurrentUser = { id: string; role: Role };

type ManualDedupKeys = {
  normalizedTitle: string;
  moduleScopeKey: string;
  targetRolesKey: string;
  contentHash: string;
};

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
    const dedupKeys = this.buildDedupKeys({
      title,
      content,
      moduleKey,
      targetRoles,
    });

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
      normalizedTitle: dedupKeys.normalizedTitle,
      moduleScopeKey: dedupKeys.moduleScopeKey,
      targetRolesKey: dedupKeys.targetRolesKey,
      contentHash: dedupKeys.contentHash,
      published: dto.published ?? true,
      sortOrder: dto.sortOrder ?? 0,
      updatedByUserId: user.id,
    };

    const duplicateWhere: Prisma.CompanyManualEntryWhereInput = {
      ownerId,
      normalizedTitle: dedupKeys.normalizedTitle,
      kind: dto.kind,
      audience: dto.audience,
      moduleScopeKey: dedupKeys.moduleScopeKey,
      targetRolesKey: dedupKeys.targetRolesKey,
      contentHash: dedupKeys.contentHash,
    };

    if (dto.id) {
      const existing = await this.prisma.companyManualEntry.findFirst({
        where: { id: dto.id, ownerId },
        select: { id: true, createdByUserId: true },
      });
      if (!existing) {
        throw new NotFoundException('La entrada del manual no existe');
      }

      const duplicated = await this.prisma.companyManualEntry.findFirst({
        where: {
          ...duplicateWhere,
          id: { not: dto.id },
        },
        select: { id: true },
      });
      if (duplicated) {
        throw new ConflictException('Ya existe una regla idéntica en el manual interno.');
      }

      return this.prisma.companyManualEntry.update({
        where: { id: dto.id },
        data: { ...data, createdByUserId: existing.createdByUserId },
      });
    }

    const duplicated = await this.prisma.companyManualEntry.findFirst({
      where: duplicateWhere,
      select: { id: true },
    });
    if (duplicated) {
      throw new ConflictException('Ya existe una regla idéntica en el manual interno.');
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
    await this.prisma.$transaction(
      async (tx) => {
        const entries: Array<
          Omit<Prisma.CompanyManualEntryCreateInput, 'normalizedTitle' | 'moduleScopeKey' | 'targetRolesKey' | 'contentHash'> & {
            starterKey: string;
          }
        > = [
          {
            starterKey: 'starter-clientes-registro-correcto',
            ownerId,
            createdByUserId: actorUserId,
            updatedByUserId: actorUserId,
            title: 'Atencion y registro correcto del cliente',
            summary: 'Toda gestion debe iniciar con datos completos y trazables del cliente.',
            content: `1. Confirmar nombre, telefono y necesidad principal antes de crear cualquier registro.
2. Evitar duplicados; si el cliente ya existe, actualizar su ficha en lugar de crear otra.
3. Registrar observaciones claras y verificables para que ventas y soporte trabajen con la misma informacion.
4. No prometer tiempos, precios o garantias fuera de lo documentado en el sistema.`,
            kind: CompanyManualEntryKind.GENERAL_RULE,
            audience: CompanyManualAudience.GENERAL,
            targetRoles: [],
            moduleKey: 'clientes',
            published: true,
            sortOrder: 1,
          },
          {
            starterKey: 'starter-cotizaciones-politica-base-precios',
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
            starterKey: 'starter-general-responsabilidad-actualizacion',
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
            sortOrder: 3,
          },
          {
            starterKey: 'starter-general-guia-rapida-modulos',
            ownerId,
            createdByUserId: actorUserId,
            updatedByUserId: actorUserId,
            title: 'Guia rapida de uso de modulos principales',
            summary: 'Clientes, cotizaciones y ventas deben mantenerse alineados en una misma cadena de trabajo.',
            content: `1. Registrar o validar el cliente antes de iniciar una cotizacion o venta.
      2. Usar cotizaciones para dejar claro el alcance comercial antes de confirmar.
      3. Mantener observaciones visibles para soporte cuando el caso requiera seguimiento posterior.
      4. Mantener consistencia entre lo cotizado, lo vendido y lo entregado.`,
            kind: CompanyManualEntryKind.MODULE_GUIDE,
            audience: CompanyManualAudience.GENERAL,
            targetRoles: [],
            moduleKey: 'general',
            published: true,
            sortOrder: 4,
          },
        ];

        for (const entry of entries) {
          const keys = this.buildDedupKeys({
            title: entry.title,
            content: entry.content,
            moduleKey: entry.moduleKey,
            targetRoles: entry.targetRoles,
          });

          await tx.companyManualEntry.upsert({
            where: {
              ownerId_starterKey: {
                ownerId,
                starterKey: entry.starterKey,
              },
            },
            create: {
              ...entry,
              normalizedTitle: keys.normalizedTitle,
              moduleScopeKey: keys.moduleScopeKey,
              targetRolesKey: keys.targetRolesKey,
              contentHash: keys.contentHash,
            },
            update: {
              title: entry.title,
              summary: entry.summary,
              content: entry.content,
              kind: entry.kind,
              audience: entry.audience,
              targetRoles: entry.targetRoles,
              moduleKey: entry.moduleKey,
              published: entry.published,
              sortOrder: entry.sortOrder,
              updatedByUserId: actorUserId,
              normalizedTitle: keys.normalizedTitle,
              moduleScopeKey: keys.moduleScopeKey,
              targetRolesKey: keys.targetRolesKey,
              contentHash: keys.contentHash,
            },
          });
        }
      },
      {
        isolationLevel: 'Serializable',
        timeout: 30000,
      },
    );
  }

  private buildDedupKeys(params: {
    title: string;
    content: string;
    moduleKey?: string | null;
    targetRoles: Role[];
  }): ManualDedupKeys {
    const normalizedTitle = this.normalizeText(params.title);
    const moduleScopeKey = this.normalizeText(params.moduleKey ?? '');
    const targetRolesItems = [...new Set((params.targetRoles ?? []).map((r) => `${r}`.trim().toUpperCase()))]
      .filter((item) => item.length > 0)
      .sort();
    const contentHash = this.hashContent(this.normalizeText(params.content));

    return {
      normalizedTitle,
      moduleScopeKey,
      targetRolesKey: targetRolesItems.join('|'),
      contentHash,
    };
  }

  private normalizeText(value: string) {
    return value
      .normalize('NFKD')
      .replace(/[\u0300-\u036f]/g, '')
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, ' ')
      .trim()
      .replace(/\s+/g, ' ');
  }

  private hashContent(value: string) {
    return createHash('sha256').update(value).digest('hex');
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