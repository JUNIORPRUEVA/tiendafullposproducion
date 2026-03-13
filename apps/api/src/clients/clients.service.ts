import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { normalizePhone } from '../common/utils/normalize-phone';
import { CreateClientDto } from './dto/create-client.dto';
import { ClientsQueryDto } from './dto/clients-query.dto';
import { UpdateClientDto } from './dto/update-client.dto';

@Injectable()
export class ClientsService {
  constructor(private readonly prisma: PrismaService) {}

  private async assertNoActiveDuplicatePhoneNormalized(
    phoneNormalized: string,
    excludeClientId?: string,
  ) {
    if (!phoneNormalized) return;

    const existing = await this.prisma.client.findFirst({
      where: {
        isDeleted: false,
        phoneNormalized,
        ...(excludeClientId ? { id: { not: excludeClientId } } : {}),
      },
      select: { id: true },
    });

    if (existing) {
      throw new ConflictException(
        `Ya existe un cliente activo con ese teléfono (${phoneNormalized}).`,
      );
    }
  }

  async create(ownerId: string, dto: CreateClientDto) {
    const phoneNormalized = normalizePhone(dto.telefono);
    await this.assertNoActiveDuplicatePhoneNormalized(phoneNormalized);
    try {
      return await this.prisma.client.create({
        data: { ...dto, ownerId, phoneNormalized, lastActivityAt: new Date() },
      });
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        throw new ConflictException('Ya existe un cliente con ese teléfono');
      }
      throw error;
    }
  }

  async findAll(query: ClientsQueryDto) {
    const page = query.page && query.page > 0 ? query.page : 1;
    const pageSize = query.pageSize && query.pageSize > 0 ? query.pageSize : 20;
    const skip = (page - 1) * pageSize;

    const search = query.search?.trim();
    const phone = query.phone?.trim();
    const phoneCandidate = phone || search;
    const phoneNormalizedSearch = normalizePhone(phoneCandidate);
    const baseWhere: Prisma.ClientWhereInput = {
      ...(query.onlyDeleted === true
        ? { isDeleted: true }
        : query.includeDeleted === true
          ? {}
          : { isDeleted: false }),
    };

    const or: Prisma.ClientWhereInput[] = [
      ...(search
        ? [
            { nombre: { contains: search, mode: Prisma.QueryMode.insensitive } },
            { telefono: { contains: search, mode: Prisma.QueryMode.insensitive } },
            { email: { contains: search, mode: Prisma.QueryMode.insensitive } },
          ]
        : []),
      ...(phoneNormalizedSearch ? [{ phoneNormalized: { contains: phoneNormalizedSearch } }] : []),
    ];

    const where: Prisma.ClientWhereInput = or.length ? { ...baseWhere, OR: or } : baseWhere;

    const [items, total] = await Promise.all([
      this.prisma.client.findMany({
        where,
        orderBy: [{ lastActivityAt: 'desc' }, { createdAt: 'desc' }],
        skip,
        take: pageSize,
      }),
      this.prisma.client.count({ where })
    ]);

    return { items, total, page, pageSize, totalPages: Math.max(1, Math.ceil(total / pageSize)) };
  }

  async findOne(id: string) {
    const client = await this.prisma.client.findFirst({ where: { id } });
    if (!client) throw new NotFoundException('Client not found');
    return client;
  }

  async update(id: string, dto: UpdateClientDto) {
    await this.findOne(id);
    const telefonoWasProvided = Object.prototype.hasOwnProperty.call(dto, 'telefono');
    const phoneNormalized = telefonoWasProvided ? normalizePhone(dto.telefono) : undefined;
    if (telefonoWasProvided) {
      await this.assertNoActiveDuplicatePhoneNormalized(phoneNormalized ?? '', id);
    }

    try {
      return await this.prisma.client.update({
        where: { id },
        data: {
          ...dto,
          ...(telefonoWasProvided ? { phoneNormalized: phoneNormalized ?? '' } : {}),
        },
      });
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        throw new ConflictException('Ya existe un cliente con ese teléfono');
      }
      throw error;
    }
  }

  async remove(id: string) {
    await this.findOne(id);
    await this.prisma.client.update({ where: { id }, data: { isDeleted: true } });
    return { ok: true };
  }

  async getProfile(id: string) {
    const client = await this.prisma.client.findFirst({
      where: { id },
      select: {
        id: true,
        nombre: true,
        telefono: true,
        phoneNormalized: true,
        email: true,
        direccion: true,
        notas: true,
        ownerId: true,
        lastActivityAt: true,
        isDeleted: true,
        createdAt: true,
        updatedAt: true,
      },
    });

    if (!client) throw new NotFoundException('Client not found');

    const [createdBy, salesAgg, servicesAgg, cotizacionesAgg] = await this.prisma.$transaction([
      this.prisma.user.findUnique({
        where: { id: client.ownerId },
        select: { id: true, nombreCompleto: true, email: true, role: true },
      }),
      this.prisma.sale.aggregate({
        where: { customerId: id, isDeleted: false },
        _count: { _all: true },
        _sum: { totalSold: true },
        _max: { saleDate: true },
      }),
      this.prisma.service.aggregate({
        where: { customerId: id, isDeleted: false },
        _count: { _all: true },
        _max: { updatedAt: true },
      }),
      this.prisma.cotizacion.aggregate({
        where: { customerId: id },
        _count: { _all: true },
        _sum: { total: true },
        _max: { updatedAt: true },
      }),
    ]);

    return {
      client,
      createdBy,
      metrics: {
        salesCount: salesAgg._count._all,
        salesTotal: salesAgg._sum.totalSold,
        lastSaleAt: salesAgg._max.saleDate,
        servicesCount: servicesAgg._count._all,
        lastServiceAt: servicesAgg._max.updatedAt,
        cotizacionesCount: cotizacionesAgg._count._all,
        cotizacionesTotal: cotizacionesAgg._sum.total,
        lastCotizacionAt: cotizacionesAgg._max.updatedAt,
        lastActivityAt: client.lastActivityAt,
      },
    };
  }

  async getTimeline(
    id: string,
    options: { take?: number; before?: string; types?: string },
  ) {
    await this.findOne(id);

    const take = Math.min(Math.max(options.take ?? 100, 1), 300);
    const before = options.before ? new Date(options.before) : new Date();
    if (Number.isNaN(before.getTime())) {
      throw new BadRequestException('before inválido');
    }
    const types = (options.types ?? '')
      .split(',')
      .map((t) => t.trim())
      .filter(Boolean);

    const rows = await this.prisma.$queryRaw<
      Array<{
        eventType: string;
        eventId: string;
        at: Date;
        title: string;
        amount: any | null;
        status: string | null;
        userId: string | null;
        userName: string | null;
        meta: any;
      }>
    >(Prisma.sql`
      SELECT *
      FROM (
        SELECT
          'sale'::text AS "eventType",
          s.id::text AS "eventId",
          s."saleDate" AS "at",
          'Venta'::text AS title,
          s."totalSold" AS amount,
          NULL::text AS status,
          u.id::text AS "userId",
                u."nombreCompleto"::text AS "userName",
          jsonb_build_object('note', s.note) AS meta
        FROM "Sale" s
              JOIN "users" u ON u.id = s."userId"
        WHERE s."customerId" = ${id}::uuid
          AND s."isDeleted" = false
          AND s."saleDate" < ${before}

        UNION ALL

        SELECT
          'cotizacion'::text AS "eventType",
          c.id::text AS "eventId",
          c."createdAt" AS "at",
          'Cotización'::text AS title,
          c.total AS amount,
          NULL::text AS status,
          u.id::text AS "userId",
                u."nombreCompleto"::text AS "userName",
          jsonb_build_object('note', c.note, 'includeItbis', c."includeItbis") AS meta
        FROM "Cotizacion" c
              JOIN "users" u ON u.id = c."createdByUserId"
        WHERE c."customerId" = ${id}::uuid
          AND c."createdAt" < ${before}

        UNION ALL

        SELECT
          'service'::text AS "eventType",
          sv.id::text AS "eventId",
          sv."createdAt" AS "at",
          sv.title::text AS title,
          sv."quotedAmount" AS amount,
          sv.status::text AS status,
          u.id::text AS "userId",
                u."nombreCompleto"::text AS "userName",
          jsonb_build_object(
            'category', sv.category,
            'orderState', sv."orderState",
            'technicianId', sv."technicianId"
          ) AS meta
        FROM "Service" sv
              JOIN "users" u ON u.id = sv."createdByUserId"
        WHERE sv."customerId" = ${id}::uuid
          AND sv."isDeleted" = false
          AND sv."createdAt" < ${before}

        UNION ALL

        SELECT
          'service_phase'::text AS "eventType",
          ph.id::text AS "eventId",
          ph."changedAt" AS "at",
          'Cambio de fase'::text AS title,
          NULL::numeric AS amount,
          COALESCE(ph."toPhase", ph.phase)::text AS status,
          u.id::text AS "userId",
                u."nombreCompleto"::text AS "userName",
          jsonb_build_object(
            'serviceId', sv.id,
            'serviceTitle', sv.title,
            'fromPhase', ph."fromPhase",
            'toPhase', ph."toPhase",
            'note', ph.note
          ) AS meta
        FROM "ServicePhaseHistory" ph
        JOIN "Service" sv ON sv.id = ph."serviceId"
              JOIN "users" u ON u.id = ph."changedByUserId"
        WHERE sv."customerId" = ${id}::uuid
          AND sv."isDeleted" = false
          AND ph."changedAt" < ${before}

        UNION ALL

        SELECT
          'service_update'::text AS "eventType",
          su.id::text AS "eventId",
          su."createdAt" AS "at",
          'Actualización'::text AS title,
          NULL::numeric AS amount,
          su.type::text AS status,
          u.id::text AS "userId",
                u."nombreCompleto"::text AS "userName",
          jsonb_build_object(
            'serviceId', sv.id,
            'serviceTitle', sv.title,
            'message', su.message,
            'oldValue', su."oldValue",
            'newValue', su."newValue"
          ) AS meta
        FROM "ServiceUpdate" su
        JOIN "Service" sv ON sv.id = su."serviceId"
              JOIN "users" u ON u.id = su."changedByUserId"
        WHERE sv."customerId" = ${id}::uuid
          AND sv."isDeleted" = false
          AND su."createdAt" < ${before}
      ) t
      WHERE (cardinality(${types}::text[]) = 0 OR t."eventType" = ANY(${types}::text[]))
      ORDER BY t."at" DESC, t."eventId" DESC
      LIMIT ${take};
    `);

    return { items: rows, before: before.toISOString(), take };
  }
}

