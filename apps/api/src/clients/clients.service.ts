import crypto from 'node:crypto';

import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Prisma, Role, type Client } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { normalizePhone } from '../common/utils/normalize-phone';
import { ClientLocationFieldsDto } from './dto/client-location-fields.dto';
import { CreateClientDto } from './dto/create-client.dto';
import { ClientsQueryDto } from './dto/clients-query.dto';
import { UpdateClientLocationDto } from './dto/update-client-location.dto';
import { UpdateClientDto } from './dto/update-client.dto';
import { CatalogRealtimeRelayService } from '../products/catalog-realtime-relay.service';

type AuthUser = { id: string; role: Role };

@Injectable()
export class ClientsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: CatalogRealtimeRelayService,
  ) {}

  private static readonly adminLikeRoles = new Set<Role>([Role.ADMIN, Role.ASISTENTE]);

  private static readonly uuidPattern =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

  private ensureValidClientId(id: string) {
    if (ClientsService.uuidPattern.test(id)) {
      return;
    }

    throw new NotFoundException('Client not found');
  }

  private isAdminLike(user: AuthUser) {
    return ClientsService.adminLikeRoles.has(user.role);
  }

  private buildTechnicianServiceOrderWhere(user: AuthUser): Prisma.ServiceOrderWhereInput {
    return {
      OR: [{ assignedToId: user.id }, { createdById: user.id }],
    };
  }

  private combineWhere(...parts: Array<Prisma.ClientWhereInput | null | undefined>): Prisma.ClientWhereInput {
    const filters = parts.filter((part): part is Prisma.ClientWhereInput => part != null);
    if (filters.length === 0) {
      return {};
    }
    if (filters.length === 1) {
      return filters[0];
    }
    return { AND: filters };
  }

  private async findClientOrThrow(id: string) {
    this.ensureValidClientId(id);

    const client = await this.prisma.client.findUnique({
      where: { id },
    });

    if (!client) {
      throw new NotFoundException('Client not found');
    }

    return client;
  }

  private async findAccessibleClientOrThrow(user: AuthUser, id: string) {
    const client = await this.findClientOrThrow(id);

    if (this.isAdminLike(user)) {
      return client;
    }

    if (user.role === Role.TECNICO) {
      const relatedOrder = await this.prisma.serviceOrder.findFirst({
        where: {
          clientId: id,
          ...this.buildTechnicianServiceOrderWhere(user),
        },
        select: { id: true },
      });

      if (!relatedOrder) {
        throw new ForbiddenException('No tienes permiso para ver este cliente');
      }

      return client;
    }

    if (client.ownerId === user.id) {
      return client;
    }

    throw new ForbiddenException('Not authorized to access this client');
  }

  private assertAdmin(user: AuthUser, message: string) {
    if (user.role !== Role.ADMIN) {
      throw new ForbiddenException(message);
    }
  }

  private toNullableNumber(
    value: Prisma.Decimal | number | string | null | undefined,
  ): number | null {
    if (value == null) return null;
    if (value instanceof Prisma.Decimal) return value.toNumber();
    const numeric = Number(value);
    return Number.isFinite(numeric) ? numeric : null;
  }

  private normalizeLocationUrl(value: string | null | undefined): string | null {
    const normalized = value?.trim();
    return normalized ? normalized : null;
  }

  private buildGoogleMapsUrl(latitude: number, longitude: number) {
    return `https://www.google.com/maps?q=${latitude},${longitude}`;
  }

  private extractCoordinatesFromLocationUrl(locationUrl: string) {
    const decoded = decodeURIComponent(locationUrl);
    const patterns = [
      /[?&]q=(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)/i,
      /@(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)/i,
      /(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)/,
    ];

    for (const pattern of patterns) {
      const match = decoded.match(pattern);
      if (!match) continue;

      const latitude = Number(match[1]);
      const longitude = Number(match[2]);

      if (
        Number.isFinite(latitude) &&
        Number.isFinite(longitude) &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180
      ) {
        return { latitude, longitude };
      }
    }

    return null;
  }

  private resolveLocationPayload(dto: ClientLocationFieldsDto, allowClear = false) {
    const latitude = dto.latitude;
    const longitude = dto.longitude;
    const locationUrlInput = dto.location_url ?? dto.locationUrl;

    const latitudeWasProvided = latitude !== undefined;
    const longitudeWasProvided = longitude !== undefined;
    const locationUrlWasProvided = locationUrlInput !== undefined;

    if (
      !latitudeWasProvided &&
      !longitudeWasProvided &&
      !locationUrlWasProvided
    ) {
      return null;
    }

    const normalizedLatitude = latitude ?? null;
    const normalizedLongitude = longitude ?? null;
    const locationUrl = this.normalizeLocationUrl(locationUrlInput);

    if (
      allowClear &&
      latitudeWasProvided &&
      longitudeWasProvided &&
      locationUrlWasProvided &&
      normalizedLatitude == null &&
      normalizedLongitude == null &&
      locationUrl == null
    ) {
      return {
        latitude: null,
        longitude: null,
        locationUrl: null,
      };
    }

    if ((normalizedLatitude == null) != (normalizedLongitude == null)) {
      throw new BadRequestException('latitude y longitude deben enviarse juntos.');
    }

    let resolvedLatitude = normalizedLatitude;
    let resolvedLongitude = normalizedLongitude;

    // If explicit coordinates are provided, use them and build URL if needed.
    if (resolvedLatitude != null && resolvedLongitude != null) {
      const finalLocationUrl = locationUrl ?? this.buildGoogleMapsUrl(resolvedLatitude, resolvedLongitude);
      return {
        latitude: new Prisma.Decimal(resolvedLatitude),
        longitude: new Prisma.Decimal(resolvedLongitude),
        locationUrl: finalLocationUrl,
      };
    }

    // Only URL provided: try to extract coordinates, but don't reject if it's a
    // short/redirect link (e.g. maps.app.goo.gl). Store the URL as-is in that case.
    if (!locationUrl) {
      throw new BadRequestException('Debe enviar latitude/longitude o location_url.');
    }

    const extracted = this.extractCoordinatesFromLocationUrl(locationUrl);

    if (extracted) {
      return {
        latitude: new Prisma.Decimal(extracted.latitude),
        longitude: new Prisma.Decimal(extracted.longitude),
        locationUrl,
      };
    }

    // URL provided but coordinates could not be extracted (e.g. short share link).
    // Store the URL without coordinates — the client app will open the link directly.
    return {
      latitude: null,
      longitude: null,
      locationUrl,
    };
  }

  private serializeClient(client: Client | null) {
    if (!client) return client;

    const latitude = this.toNullableNumber(client.latitude);
    const longitude = this.toNullableNumber(client.longitude);
    const locationUrl = client.locationUrl ?? null;

    return {
      ...client,
      latitude,
      longitude,
      locationUrl,
      location_url: locationUrl,
    };
  }

  private serializeClientCollection(clients: Client[]) {
    return clients.map((client) => this.serializeClient(client));
  }

  private emitClientEvent(type: string, client?: Client | null, clientId?: string) {
    const serialized = this.serializeClient(client ?? null);
    const resolvedClientId = clientId?.trim() || serialized?.id?.toString().trim() || undefined;
    this.realtime.emitOps('client.event', {
      eventId: crypto.randomUUID(),
      type,
      clientId: resolvedClientId,
      client: serialized,
    });
  }

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

  async create(user: AuthUser, dto: CreateClientDto) {
    const phoneNormalized = normalizePhone(dto.telefono);
    const locationData = this.resolveLocationPayload(dto);
    await this.assertNoActiveDuplicatePhoneNormalized(phoneNormalized);
    try {
      const client = await this.prisma.client.create({
        data: {
          nombre: dto.nombre,
          telefono: dto.telefono,
          email: dto.email,
          direccion: dto.direccion,
          notas: dto.notas,
          ownerId: user.id,
          phoneNormalized,
          lastActivityAt: new Date(),
          ...(locationData ?? {}),
        },
      });
      this.emitClientEvent('client.created', client);
      return this.serializeClient(client);
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        throw new ConflictException('Ya existe un cliente con ese teléfono');
      }
      throw error;
    }
  }

  async findAll(user: AuthUser, query: ClientsQueryDto) {
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

    const where = this.combineWhere(baseWhere, or.length ? { OR: or } : null);

    const [items, total] = await Promise.all([
      this.prisma.client.findMany({
        where,
        orderBy: [{ lastActivityAt: 'desc' }, { createdAt: 'desc' }],
        skip,
        take: pageSize,
      }),
      this.prisma.client.count({ where }),
    ]);

    return {
      items: this.serializeClientCollection(items),
      total,
      page,
      pageSize,
      totalPages: Math.max(1, Math.ceil(total / pageSize)),
    };
  }

  async findOne(user: AuthUser, id: string) {
    const client = await this.findClientOrThrow(id);
    return this.serializeClient(client);
  }

  async update(user: AuthUser, id: string, dto: UpdateClientDto) {
    await this.findAccessibleClientOrThrow(user, id);
    const telefonoWasProvided = Object.prototype.hasOwnProperty.call(dto, 'telefono');
    const phoneNormalized = telefonoWasProvided ? normalizePhone(dto.telefono) : undefined;
    const locationData = this.resolveLocationPayload(dto, true);
    if (telefonoWasProvided) {
      await this.assertNoActiveDuplicatePhoneNormalized(phoneNormalized ?? '', id);
    }

    try {
      const client = await this.prisma.client.update({
        where: { id },
        data: {
          nombre: dto.nombre,
          telefono: dto.telefono,
          email: dto.email,
          direccion: dto.direccion,
          notas: dto.notas,
          ...(telefonoWasProvided ? { phoneNormalized: phoneNormalized ?? '' } : {}),
          ...(locationData ?? {}),
        },
      });
      this.emitClientEvent('client.updated', client);
      return this.serializeClient(client);
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        throw new ConflictException('Ya existe un cliente con ese teléfono');
      }
      throw error;
    }
  }

  async updateLocation(user: AuthUser, id: string, dto: UpdateClientLocationDto) {
    await this.findAccessibleClientOrThrow(user, id);
    const locationData = this.resolveLocationPayload(dto, true);

    if (!locationData) {
      throw new BadRequestException('Debe enviar latitude/longitude o location_url.');
    }

    const client = await this.prisma.client.update({
      where: { id },
      data: locationData,
    });

    this.emitClientEvent('client.updated', client);

    return this.serializeClient(client);
  }

  async remove(user: AuthUser, id: string) {
    this.assertAdmin(user, 'Only admin can delete clients');
    await this.findAccessibleClientOrThrow(user, id);
    const client = await this.prisma.client.update({ where: { id }, data: { isDeleted: true } });
    this.emitClientEvent('client.deleted', client, id);
    return { ok: true };
  }

  async purgeAllForDebug(user: AuthUser) {
    this.assertAdmin(user, 'Only admin can purge clients');

    const clients = await this.prisma.client.findMany({
      select: { id: true },
    });
    const clientIds = clients.map((item) => item.id);

    if (clientIds.length === 0) {
      return {
        ok: true,
        deletedClients: 0,
        deletedQuotations: 0,
        deletedServiceOrders: 0,
        deletedLegacyServices: 0,
      };
    }

    const quotations = await this.prisma.cotizacion.findMany({
      where: { customerId: { in: clientIds } },
      select: { id: true },
    });
    const quotationIds = quotations.map((item) => item.id);
    const serviceOrderWhere: Prisma.ServiceOrderWhereInput =
      quotationIds.length > 0
        ? {
            OR: [
              { clientId: { in: clientIds } },
              { quotationId: { in: quotationIds } },
            ],
          }
        : { clientId: { in: clientIds } };

    const result = await this.prisma.$transaction(async (tx) => {
      const deletedServiceOrders = await tx.serviceOrder.deleteMany({
        where: serviceOrderWhere,
      });
      const deletedLegacyServices = await tx.service.deleteMany({
        where: { customerId: { in: clientIds } },
      });
      const deletedQuotations = await tx.cotizacion.deleteMany({
        where: { customerId: { in: clientIds } },
      });
      const deletedClients = await tx.client.deleteMany({
        where: { id: { in: clientIds } },
      });

      return {
        deletedClients: deletedClients.count,
        deletedQuotations: deletedQuotations.count,
        deletedServiceOrders: deletedServiceOrders.count,
        deletedLegacyServices: deletedLegacyServices.count,
      };
    });

    this.emitClientEvent('client.bulkDeleted');

    return { ok: true, ...result };
  }

  async getProfile(user: AuthUser, id: string) {
    const client = await this.prisma.client.findUnique({
      where: { id },
      select: {
        id: true,
        nombre: true,
        telefono: true,
        phoneNormalized: true,
        email: true,
        direccion: true,
        notas: true,
        latitude: true,
        longitude: true,
        locationUrl: true,
        ownerId: true,
        lastActivityAt: true,
        isDeleted: true,
        createdAt: true,
        updatedAt: true,
      },
    });

    if (!client) {
      throw new NotFoundException('Client not found');
    }

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
        _max: { createdAt: true },
      }),
      this.prisma.cotizacion.aggregate({
        where: { customerId: id },
        _count: { _all: true },
        _sum: { total: true },
        _max: { updatedAt: true },
      }),
    ]);

    return {
      client: this.serializeClient(client),
      createdBy,
      metrics: {
        salesCount: salesAgg._count._all,
        salesTotal: salesAgg._sum.totalSold,
        lastSaleAt: salesAgg._max.saleDate,
        servicesCount: servicesAgg._count._all,
        lastServiceAt: servicesAgg._max.createdAt,
        cotizacionesCount: cotizacionesAgg._count._all,
        cotizacionesTotal: cotizacionesAgg._sum.total,
        lastCotizacionAt: cotizacionesAgg._max.updatedAt,
        lastActivityAt: client.lastActivityAt,
      },
    };
  }

  async getTimeline(
    user: AuthUser,
    id: string,
    options: { take?: number; before?: string; types?: string },
  ) {
    await this.findClientOrThrow(id);

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
          s.id::text AS "eventId",
          s."createdAt" AS "at",
          COALESCE(NULLIF(s."title", ''), 'Orden de servicio')::text AS title,
          COALESCE(s."quotedAmount", s."depositAmount") AS amount,
          s."orderState"::text AS status,
          u.id::text AS "userId",
          u."nombreCompleto"::text AS "userName",
          jsonb_build_object(
            'orderNumber', s."orderNumber",
            'category', s."category",
            'serviceType', s."serviceType",
            'currentPhase', s."currentPhase"
          ) AS meta
        FROM "Service" s
              JOIN "users" u ON u.id = s."createdByUserId"
        WHERE s."customerId" = ${id}::uuid
          AND s."isDeleted" = false
          AND s."createdAt" < ${before}

      ) t
      WHERE (cardinality(${types}::text[]) = 0 OR t."eventType" = ANY(${types}::text[]))
      ORDER BY t."at" DESC, t."eventId" DESC
      LIMIT ${take};
    `);

    return { items: rows, before: before.toISOString(), take };
  }
}
