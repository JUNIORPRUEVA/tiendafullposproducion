import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { createHash } from 'node:crypto';
import {
  Prisma,
  AdminOrderPhase,
  AdminOrderStatus,
  OrderState,
  OrderType,
  Role,
  ServicePhaseType,
  ServiceAssignmentRole,
  ServiceStatus,
  ServiceType,
  ServiceUpdateType,
} from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import { NotificationsService } from '../notifications/notifications.service';
import { R2Service } from '../storage/r2.service';
import { ServiceClosingService } from '../service-closing/service-closing.service';
import { ServicesQueryDto } from './dto/services-query.dto';
import { CreateServiceDto } from './dto/create-service.dto';
import { ChangeServiceStatusDto } from './dto/change-service-status.dto';
import { ChangeServiceOrderStateDto } from './dto/change-service-order-state.dto';
import { ChangeServicePhaseDto } from './dto/change-service-phase.dto';
import { ChangeServiceAdminPhaseDto } from './dto/change-service-admin-phase.dto';
import { ChangeServiceAdminStatusDto } from './dto/change-service-admin-status.dto';
import { ScheduleServiceDto } from './dto/schedule-service.dto';
import { AssignServiceDto } from './dto/assign-service.dto';
import { ServiceUpdateDto } from './dto/service-update.dto';
import { CreateWarrantyDto } from './dto/create-warranty.dto';
import { UpdateServiceDto } from './dto/update-service.dto';
import { UpsertExecutionReportDto } from './dto/upsert-execution-report.dto';
import { CreateExecutionChangeDto } from './dto/create-execution-change.dto';
import { OperationsRealtimeService } from './operations-realtime.service';

type AuthUser = { id: string; role: Role };
type ServiceCategoryLookup = { id: string; name: string; code: string };

const defaultSteps = [
  { stepKey: 'survey_done', stepLabel: 'Levantamiento completado' },
  { stepKey: 'materials_ready', stepLabel: 'Materiales listos' },
  { stepKey: 'installed', stepLabel: 'Instalación ejecutada' },
  { stepKey: 'tested', stepLabel: 'Pruebas realizadas' },
  { stepKey: 'customer_trained', stepLabel: 'Cliente instruido' },
];

const defaultServiceCategories = [
  { code: 'cameras', name: 'Cámaras' },
  { code: 'gate_motor', name: 'Motores de puertones' },
  { code: 'alarm', name: 'Alarma' },
  { code: 'electric_fence', name: 'Cerco eléctrico' },
  { code: 'intercom', name: 'Intercom' },
  { code: 'pos', name: 'Punto de ventas' },
];

const ORDERS_LIST_CACHE_PATTERN = 'orders:list:*';
const DASHBOARD_OPERATIONS_CACHE_PATTERN = 'dashboard:operations:*';

@Injectable()
export class OperationsService {
  private readonly logger = new Logger(OperationsService.name);
  private _techViewAllCache: { value: boolean; at: number } | null = null;

  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly notifications: NotificationsService,
    private readonly r2: R2Service,
    private readonly serviceClosing: ServiceClosingService,
    private readonly realtime: OperationsRealtimeService,
  ) {}

  private buildOrdersListCacheKey(user: AuthUser, query: ServicesQueryDto, techViewAll: boolean) {
    const scope = {
      userId: user.id,
      role: user.role,
      techViewAll,
      status: query.status ?? null,
      type: query.type ?? null,
      priority: query.priority ?? null,
      assignedTo: query.assignedTo ?? null,
      orderType: query.orderType ?? null,
      orderState: query.orderState ?? null,
      adminPhase: query.adminPhase ?? null,
      adminStatus: query.adminStatus ?? null,
      technicianId: query.technicianId ?? null,
      from: query.from ?? null,
      to: query.to ?? null,
      customerId: query.customerId ?? null,
      search: query.search?.trim() ?? null,
      category: query.category?.trim() ?? null,
      sellerId: query.sellerId ?? null,
      includeDeleted: query.includeDeleted === true,
      page: query.page && query.page > 0 ? query.page : 1,
      pageSize: query.pageSize && query.pageSize > 0 ? query.pageSize : 30,
    };
    const hash = createHash('sha1').update(JSON.stringify(scope)).digest('hex');
    return `orders:list:${hash}`;
  }

  private buildDashboardCacheKey(user: AuthUser, from?: string, to?: string, techViewAll: boolean = false) {
    const key = `dashboard:operations:${from ?? ''}:${to ?? ''}`;
    const scope = {
      key,
      userId: user.id,
      role: user.role,
      techViewAll,
    };
    const hash = createHash('sha1').update(JSON.stringify(scope)).digest('hex');
    return `dashboard:operations:${hash}`;
  }

  private async invalidateOrdersListCache(reason: string) {
    const deleted = await this.redis.delByPattern(ORDERS_LIST_CACHE_PATTERN);
    if (this.redis.isEnabled()) {
      this.logger.log(`Redis INVALIDATE ${ORDERS_LIST_CACHE_PATTERN} reason=${reason} deleted=${deleted}`);
    }
  }

  private async invalidateDashboardCache(reason: string) {
    const deleted = await this.redis.delByPattern(DASHBOARD_OPERATIONS_CACHE_PATTERN);
    if (this.redis.isEnabled()) {
      this.logger.log(`Redis INVALIDATE ${DASHBOARD_OPERATIONS_CACHE_PATTERN} reason=${reason} deleted=${deleted}`);
    }
  }

  private async invalidateOperationsCache(reason: string) {
    await Promise.all([
      this.invalidateOrdersListCache(reason),
      this.invalidateDashboardCache(reason),
    ]);
  }

  private async notifyFleetNumbersForService(params: {
    serviceId: string;
    createdByUserId: string;
    messageText: string;
    payload?: unknown;
  }) {
    const serviceId = (params.serviceId ?? '').toString().trim();
    const createdByUserId = (params.createdByUserId ?? '').toString().trim();
    const messageText = (params.messageText ?? '').toString().trim();
    if (!serviceId || !createdByUserId || !messageText) return;

    try {
      const [creator, staff] = await Promise.all([
        this.prisma.user.findUnique({
          where: { id: createdByUserId },
          select: { id: true, blocked: true, numeroFlota: true, role: true },
        }),
        this.prisma.user.findMany({
          where: {
            blocked: false,
            role: { in: [Role.ADMIN, Role.ASISTENTE] },
          },
          select: { id: true, blocked: true, numeroFlota: true, role: true },
        }),
      ]);

      const recipients = new Map<string, { id: string; numeroFlota: string }>();

      const add = (u: any) => {
        if (!u || u.blocked) return;
        const n = (u.numeroFlota ?? '').toString().trim();
        if (!n) return;
        const id = (u.id ?? '').toString().trim();
        if (!id) return;
        recipients.set(id, { id, numeroFlota: n });
      };

      add(creator);
      for (const u of staff ?? []) add(u);

      const payload = (params.payload ?? null) as any;
      const withService =
        payload && typeof payload === 'object'
          ? { ...payload, serviceId }
          : { kind: 'service_notification', serviceId };

      for (const r of recipients.values()) {
        void this.notifications
          .enqueueWhatsAppRawText({
            toNumber: r.numeroFlota,
            messageText,
            payload: withService,
          })
          .catch(() => {
            // ignore
          });
      }
    } catch {
      // ignore
    }
  }

  private async notifyAllTechniciansForNewService(params: {
    serviceId: string;
    createdByUserId: string;
    serviceTitle: string;
    serviceTypeLabel: string;
    customerName: string;
    actorUserId?: string;
  }) {
    const serviceId = (params.serviceId ?? '').toString().trim();
    const createdByUserId = (params.createdByUserId ?? '').toString().trim();
    if (!serviceId || !createdByUserId) return;

    try {
      const [actor, techs] = await Promise.all([
        this.prisma.user
          .findUnique({ where: { id: params.actorUserId ?? createdByUserId }, select: { nombreCompleto: true } })
          .catch(() => null),
        this.prisma.user.findMany({
          where: { blocked: false, role: Role.TECNICO },
          select: { id: true, blocked: true, numeroFlota: true },
        }),
      ]);

      const actorName = (actor?.nombreCompleto ?? '').toString().trim();
      const title = (params.serviceTitle ?? '').toString().trim() || 'Servicio';
      const typeLabel = (params.serviceTypeLabel ?? '').toString().trim() || 'Orden';
      const customerName = (params.customerName ?? '').toString().trim() || 'Cliente';

      const messageText = [
        '*Nueva orden creada*',
        `Tipo: ${typeLabel}`,
        `Servicio: ${title}`,
        `Cliente: ${customerName}`,
        actorName ? `Creada por: ${actorName}` : null,
      ]
        .filter(Boolean)
        .join('\n');

      const payload = { kind: 'new_service_created', serviceId, actorUserId: params.actorUserId ?? createdByUserId };

      for (const u of techs ?? []) {
        if (!u || u.blocked) continue;
        const n = (u.numeroFlota ?? '').toString().trim();
        if (!n) continue;

        void this.notifications
          .enqueueWhatsAppRawText({
            toNumber: n,
            messageText,
            payload,
            dedupeKey: `new_service_created:${serviceId}:${u.id}`,
          })
          .catch(() => {
            // ignore
          });
      }
    } catch {
      // ignore
    }
  }

  private async decorateServiceFilesForView(service: any) {
    const files = Array.isArray(service?.files) ? service.files : [];
    if (files.length === 0) return service;

    const expiresInSecondsRaw = (process.env.STORAGE_READ_PRESIGN_EXPIRES_SECONDS ?? '').trim();
    const expiresInSeconds = Number.isFinite(Number(expiresInSecondsRaw)) && Number(expiresInSecondsRaw) > 0
      ? Math.floor(Number(expiresInSecondsRaw))
      : 60 * 60;

    const decorated = await Promise.all(
      files.map(async (f: any) => {
        const fileUrl = typeof f?.fileUrl === 'string' ? f.fileUrl.trim() : '';
        const objectKey = typeof f?.objectKey === 'string' ? f.objectKey.trim() : '';
        const provider = typeof f?.storageProvider === 'string' ? f.storageProvider.trim() : '';

        if (provider !== 'R2' || !objectKey) return f;
        if (fileUrl.startsWith('http://') || fileUrl.startsWith('https://')) return f;

        try {
          const signed = await this.r2.createPresignedGetUrl({
            objectKey,
            expiresInSeconds,
          });
          return { ...f, fileUrl: signed };
        } catch {
          // Fallback: keep original value.
          return f;
        }
      }),
    );

    return { ...service, files: decorated };
  }

  private isAdminLike(role: Role) {
    return role === Role.ADMIN || role === Role.ASISTENTE;
  }

  private async techCanViewAllServices(): Promise<boolean> {
    const now = Date.now();
    const cached = this._techViewAllCache;
    if (cached && now - cached.at < 10_000) return cached.value;

    try {
      const cfg = await this.prisma.appConfig.findUnique({
        where: { id: 'global' },
        select: { operationsTechCanViewAllServices: true },
      });
      const value = !!cfg?.operationsTechCanViewAllServices;
      this._techViewAllCache = { value, at: now };
      return value;
    } catch {
      this._techViewAllCache = { value: false, at: now };
      return false;
    }
  }

  private isSchemaMismatch(error: unknown) {
    if (error instanceof Prisma.PrismaClientKnownRequestError) {
      return error.code === 'P2021' || error.code === 'P2022';
    }

    if (typeof error === 'object' && error !== null) {
      const value = error as { code?: unknown; message?: unknown };
      const code = typeof value.code === 'string' ? value.code : '';
      const message = typeof value.message === 'string' ? value.message : '';
      return (
        code === 'P2021' ||
        code === 'P2022' ||
        message.includes('does not exist in the current database') ||
        message.includes('column')
      );
    }

    return false;
  }

  private defaultAdminPhaseForOrderType(orderType: OrderType): AdminOrderPhase {
    return orderType === OrderType.RESERVA
      ? AdminOrderPhase.RESERVA
      : AdminOrderPhase.PROGRAMACION;
  }

  private defaultAdminStatusForAssignment(hasTechnician: boolean): AdminOrderStatus {
    return hasTechnician ? AdminOrderStatus.ASIGNADA : AdminOrderStatus.PENDIENTE;
  }

  private normalizeCategoryCode(raw: string) {
    return raw
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '_')
      .replace(/^_+|_+$/g, '');
  }

  private async ensureDefaultServiceCategories() {
    await Promise.all(
      defaultServiceCategories.map((category) =>
        this.prisma.serviceCategory.upsert({
          where: { code: category.code },
          update: { name: category.name },
          create: category,
          select: { id: true },
        }),
      ),
    );
  }

  private async resolveServiceCategory(params: {
    categoryId?: string | null;
    category?: string | null;
  }): Promise<ServiceCategoryLookup | null> {
    const categoryId = (params.categoryId ?? '').trim();
    const categoryLabel = (params.category ?? '').trim();

    await this.ensureDefaultServiceCategories();

    if (categoryId) {
      const category = await this.prisma.serviceCategory.findUnique({
        where: { id: categoryId },
        select: { id: true, name: true, code: true },
      });
      if (!category) throw new BadRequestException('Categoría inválida');
      return category;
    }

    const normalizedCode = this.normalizeCategoryCode(categoryLabel);
    if (!normalizedCode) return null;

    const category = await this.prisma.serviceCategory.findFirst({
      where: {
        OR: [
          { code: normalizedCode },
          { name: { equals: categoryLabel, mode: Prisma.QueryMode.insensitive } },
        ],
      },
      select: { id: true, name: true, code: true },
    });
    if (!category) throw new BadRequestException('Categoría inválida');
    return category;
  }

  private assertAdminPhaseTransition(params: {
    orderType: OrderType;
    current: AdminOrderPhase | null;
    next: AdminOrderPhase;
  }) {
    const { orderType, current, next } = params;

    // First-time backfill: allow setting when current is null.
    if (!current) {
      if (orderType !== OrderType.RESERVA && next === AdminOrderPhase.RESERVA) {
        throw new BadRequestException('La fase "reserva" solo aplica a tipo de orden "reserva"');
      }
      return;
    }

    if (current === next) {
      throw new BadRequestException('La fase seleccionada ya es la actual');
    }

    if (current === AdminOrderPhase.CANCELADA) {
      throw new BadRequestException('No se puede cambiar la fase de una orden cancelada');
    }
    if (current === AdminOrderPhase.CIERRE) {
      throw new BadRequestException('No se puede cambiar la fase de una orden cerrada');
    }

    if (next === AdminOrderPhase.CANCELADA) {
      // Cancelar corta el flujo en cualquier fase, excepto cierre.
      return;
    }

    if (orderType !== OrderType.RESERVA && next === AdminOrderPhase.RESERVA) {
      throw new BadRequestException('La fase "reserva" solo aplica a tipo de orden "reserva"');
    }

    const linear: AdminOrderPhase[] = [
      AdminOrderPhase.RESERVA,
      AdminOrderPhase.CONFIRMACION,
      AdminOrderPhase.PROGRAMACION,
      AdminOrderPhase.EJECUCION,
      AdminOrderPhase.REVISION,
      AdminOrderPhase.FACTURACION,
      AdminOrderPhase.CIERRE,
    ];

    const fromIndex = linear.indexOf(current);
    const toIndex = linear.indexOf(next);
    if (fromIndex < 0 || toIndex < 0) {
      throw new BadRequestException('Transición de fase inválida');
    }

    if (toIndex !== fromIndex + 1) {
      throw new BadRequestException('Solo se permite avanzar a la siguiente fase');
    }
  }

  async list(user: AuthUser, query: ServicesQueryDto) {
    const techViewAll = user.role === Role.TECNICO ? await this.techCanViewAllServices() : false;
    const page = query.page && query.page > 0 ? query.page : 1;
    const pageSize = query.pageSize && query.pageSize > 0 ? query.pageSize : 30;
    const skip = (page - 1) * pageSize;
    const cacheKey = this.buildOrdersListCacheKey(user, query, techViewAll);

    const cached = await this.redis.get<{
      items: any[];
      total: number;
      page: number;
      pageSize: number;
      totalPages: number;
    }>(cacheKey);

    if (cached) {
      if (this.redis.isEnabled()) {
        this.logger.log(`Redis HIT ${cacheKey}`);
      }
      return cached;
    }

    if (this.redis.isEnabled()) {
      this.logger.log(`Redis MISS ${cacheKey}`);
    }

    const where: Prisma.ServiceWhereInput = {
      ...this.scopeWhere(user, techViewAll),
      ...(query.includeDeleted ? {} : { isDeleted: false }),
      ...(query.status ? { status: this.parseStatus(query.status) } : {}),
      ...(query.type ? { serviceType: this.parseType(query.type) } : {}),
      ...(query.orderType ? this.orderTypeWhere(query.orderType) : {}),
      ...(query.orderState ? { orderState: this.parseOrderState(query.orderState) } : {}),
      ...(query.adminPhase ? { adminPhase: this.parseAdminPhase(query.adminPhase) } : {}),
      ...(query.adminStatus ? { adminStatus: this.parseAdminStatus(query.adminStatus) } : {}),
      ...(query.technicianId ? { technicianId: query.technicianId } : {}),
      ...(query.priority ? { priority: query.priority } : {}),
      ...(query.assignedTo ? { assignments: { some: { userId: query.assignedTo } } } : {}),
      ...(query.customerId ? { customerId: query.customerId } : {}),
      ...(query.sellerId ? { createdByUserId: query.sellerId } : {}),
      ...(query.category ? { category: { equals: query.category, mode: Prisma.QueryMode.insensitive } } : {}),
      ...(query.search?.trim()
        ? {
            OR: [
              { title: { contains: query.search.trim(), mode: Prisma.QueryMode.insensitive } },
              { description: { contains: query.search.trim(), mode: Prisma.QueryMode.insensitive } },
              { customer: { nombre: { contains: query.search.trim(), mode: Prisma.QueryMode.insensitive } } },
              { customer: { telefono: { contains: query.search.trim(), mode: Prisma.QueryMode.insensitive } } },
            ],
          }
        : {}),
      ...this.scheduleRangeWhere(query.from, query.to),
    };

    let items: any[] = [];
    let total = 0;

    try {
      [items, total] = await Promise.all([
        this.prisma.service.findMany({
          where,
          include: this.serviceInclude(),
          orderBy: [{ priority: 'asc' }, { createdAt: 'desc' }],
          skip,
          take: pageSize,
        }),
        this.prisma.service.count({ where }),
      ]);
    } catch (error) {
      if (!this.isSchemaMismatch(error)) throw error;
      items = [];
      total = 0;
    }

    const response = {
      items: items.map((item) => this.normalizeService(item)),
      total,
      page,
      pageSize,
      totalPages: Math.max(1, Math.ceil(total / pageSize)),
    };

    await this.redis.set(cacheKey, response);

    return response;
  }

  async listTechnicians(_user: AuthUser) {
    const items = await this.prisma.user.findMany({
      where: { role: Role.TECNICO, blocked: false },
      select: { id: true, nombreCompleto: true },
      orderBy: { nombreCompleto: 'asc' },
    });
    return { items };
  }

  async findOne(user: AuthUser, id: string) {
    const service = await this.prisma.service.findFirst({
      where: { id, isDeleted: false },
      include: this.serviceInclude(),
    });

    if (!service) throw new NotFoundException('Servicio no encontrado');

    const techViewAll = user.role === Role.TECNICO ? await this.techCanViewAllServices() : false;
    this.assertCanView(user, service.createdByUserId, service.assignments.map((a) => a.userId), techViewAll);

    const hydrated = await this.decorateServiceFilesForView(service);
    const normalized = this.normalizeService(hydrated);

    // Best-effort: closing workflow summary (won't break servers missing migrations).
    try {
      const summary = await this.serviceClosing.getSummaryBestEffort(id);
      return { ...normalized, closing: summary };
    } catch {
      return normalized;
    }
  }

  async create(user: AuthUser, dto: CreateServiceDto) {
    const customer = await this.prisma.client.findUnique({ where: { id: dto.customerId } });
    if (!customer || customer.isDeleted) {
      throw new BadRequestException('Cliente inválido');
    }

    const category = await this.resolveServiceCategory({
      categoryId: dto.categoryId,
      category: dto.category,
    });
    if (!category) {
      throw new BadRequestException('La categoría es requerida');
    }

    if (dto.warrantyParentServiceId) {
      const parent = await this.prisma.service.findFirst({
        where: { id: dto.warrantyParentServiceId, isDeleted: false },
      });
      if (!parent) throw new BadRequestException('Servicio padre no encontrado');
    }

    const priority = dto.priority ?? (dto.serviceType === 'installation' ? 1 : 2);

    const surveyResult = dto.surveyResult?.trim();
    const materialsUsed = dto.materialsUsed?.trim();
    const finalCost = dto.finalCost;
    const orderExtras: Record<string, unknown> = {};
    if (surveyResult) orderExtras.surveyResult = surveyResult;
    if (materialsUsed) orderExtras.materialsUsed = materialsUsed;
    if (finalCost != null) orderExtras.finalCost = finalCost;
    const hasOrderExtras = Object.keys(orderExtras).length > 0;

    let technicianId: string | null = null;
    if (dto.technicianId) {
      const tech = await this.prisma.user.findFirst({
        where: { id: dto.technicianId, role: Role.TECNICO, blocked: false },
        select: { id: true },
      });
      if (!tech) throw new BadRequestException('Técnico inválido');
      technicianId = tech.id;
    }

    const created = await this.prisma.$transaction(async (tx) => {
      const baseData: Prisma.ServiceCreateInput = {
        customer: { connect: { id: dto.customerId } },
        createdBy: { connect: { id: user.id } },
        serviceType: this.parseType(dto.serviceType),
        category: category.code,
        categoryRef: { connect: { id: category.id } },
        status: ServiceStatus.RESERVED,
        priority,
        title: dto.title.trim(),
        description: dto.description.trim(),
        quotedAmount: dto.quotedAmount,
        depositAmount: dto.depositAmount,
        paymentStatus: dto.paymentStatus ?? 'pending',
        addressSnapshot: dto.addressSnapshot?.trim() || customer.direccion,
        tags: dto.tags ?? [],
        steps: {
          create: defaultSteps,
        },
        updates: {
          create: {
            changedByUserId: user.id,
            type: ServiceUpdateType.STATUS_CHANGE,
            oldValue: Prisma.DbNull,
            newValue: { status: 'reserved' },
            message: 'Reserva creada',
          },
        },
      };

      const orderType = dto.orderType ? this.parseOrderType(dto.orderType) : OrderType.RESERVA;
      const adminPhase = dto.adminPhase
        ? this.parseAdminPhase(dto.adminPhase)
        : this.defaultAdminPhaseForOrderType(orderType);
      const adminStatus = dto.adminStatus
        ? this.parseAdminStatus(dto.adminStatus)
        : this.defaultAdminStatusForAssignment(!!technicianId);
      const orderState = dto.orderState
        ? this.parseOrderState(dto.orderState)
        : (!!technicianId ? OrderState.ASSIGNED : OrderState.PENDING);

      const createWithOrderFields = {
        ...baseData,
        orderType,
        orderState,
        adminPhase,
        adminStatus,
        ...(hasOrderExtras ? { orderExtras: orderExtras as Prisma.InputJsonValue } : {}),
        ...(dto.warrantyParentServiceId
          ? { warrantyParent: { connect: { id: dto.warrantyParentServiceId } } }
          : {}),
        ...(technicianId ? { technician: { connect: { id: technicianId } } } : {}),
      } as any;

      let service: any;
      try {
        for (let attempt = 0; attempt < 5; attempt++) {
          try {
            service = await tx.service.create({
              data: {
                ...createWithOrderFields,
                orderNumber: this.generateOrderNumber(new Date()),
              } as any,
              include: this.serviceInclude(),
            });
            break;
          } catch (err) {
            if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') {
              continue;
            }
            throw err;
          }
        }
        if (!service) {
          service = await tx.service.create({
            data: createWithOrderFields,
            include: this.serviceInclude(),
          });
        }
      } catch (error) {
        if (!this.isSchemaMismatch(error)) throw error;
        service = await tx.service.create({
          data: baseData,
          include: this.serviceInclude(),
        });
      }

      try {
        await tx.servicePhaseHistory.create({
          data: {
            serviceId: service.id,
            phase: ServicePhaseType.RESERVA,
            note: 'Fase inicial automática',
            changedByUserId: user.id,
            fromPhase: null,
            toPhase: ServicePhaseType.RESERVA,
          },
        });
      } catch (error) {
        if (!this.isSchemaMismatch(error)) throw error;
      }

      if (technicianId) {
        await tx.serviceAssignment.create({
          data: {
            serviceId: service.id,
            userId: technicianId,
            role: ServiceAssignmentRole.LEAD,
          },
        });
      }

      const finalRow = technicianId
        ? await tx.service.findUnique({ where: { id: service.id }, include: this.serviceInclude() })
        : service;

      if (!finalRow) throw new NotFoundException('Servicio no encontrado');

      await tx.client.update({
        where: { id: dto.customerId },
        data: { lastActivityAt: finalRow.createdAt },
      });
      return finalRow;
    });

    const normalized = this.normalizeService(created);
    try {
      this.realtime.emitServiceEvent({
        type: 'service.created',
        service: normalized,
        actorUserId: user.id,
      });
    } catch {
      // ignore
    }

    // Notify all technicians (fleet numbers) that a new order was created.
    try {
      const typeLabel = (() => {
        const t = this.toApiType(created.serviceType);
        switch (t) {
          case 'survey':
            return 'Levantamiento';
          case 'warranty':
            return 'Garantía';
          case 'installation':
            return 'Instalación';
          case 'maintenance':
            return 'Mantenimiento';
          default:
            return t || 'Orden';
        }
      })();

      await this.notifyAllTechniciansForNewService({
        serviceId: created.id,
        createdByUserId: created.createdByUserId,
        serviceTitle: created.title,
        serviceTypeLabel: typeLabel,
        customerName: created.customer?.nombre ?? 'Cliente',
        actorUserId: user.id,
      });
    } catch {
      // ignore
    }

    await this.invalidateOperationsCache('service.create');

    return normalized;
  }

  async changePhase(user: AuthUser, id: string, dto: ChangeServicePhaseDto) {
    const scheduledAtRaw = (dto.scheduledAt ?? '').trim();
    if (!scheduledAtRaw) {
      throw new BadRequestException('scheduledAt es requerido');
    }

    const scheduledAt = new Date(scheduledAtRaw);
    if (Number.isNaN(scheduledAt.getTime())) {
      throw new BadRequestException('scheduledAt inválido');
    }

    const service = await this.prisma.service.findFirst({
      where: { id, isDeleted: false },
      include: {
        customer: { select: { id: true, direccion: true } },
      },
    });

    if (!service) throw new NotFoundException('Servicio no encontrado');
    if (user.role !== Role.ADMIN && user.role !== Role.ASISTENTE && user.id !== service.createdByUserId) {
      throw new ForbiddenException('No autorizado para cambiar la fase');
    }

    const nextPhase = this.parsePhase(dto.phase);
    if (nextPhase === ServicePhaseType.RESERVA) {
      throw new BadRequestException('Reserva es solo fase inicial');
    }
    if (service.currentPhase === nextPhase) {
      throw new BadRequestException('La fase seleccionada ya es la actual');
    }

    const extractMoney = (value: unknown): number | null => {
      if (value == null) return null;
      if (typeof value === 'number') return Number.isFinite(value) ? value : null;
      if (typeof value === 'string') {
        const parsed = Number(value);
        return Number.isFinite(parsed) ? parsed : null;
      }
      if (typeof value === 'object') {
        // Prisma Decimal and other numeric-like objects.
        const asAny = value as { toNumber?: () => number; toString?: () => string };
        if (typeof asAny.toNumber === 'function') {
          const n = asAny.toNumber();
          return Number.isFinite(n) ? n : null;
        }
        if (typeof asAny.toString === 'function') {
          const parsed = Number(asAny.toString());
          return Number.isFinite(parsed) ? parsed : null;
        }
      }
      return null;
    };

    const orderExtras = (service as any).orderExtras as any;
    const finalCost = extractMoney(orderExtras?.finalCost);

    const locationText = [service.addressSnapshot, service.customer?.direccion]
      .map((v) => (v ?? '').toString().trim())
      .find((v) => v.length > 0);

    const locationOk = (text: string | undefined) => {
      const raw = (text ?? '').trim();
      if (!raw) return false;
      // Either a non-empty address, or GPS, or an URL.
      if (/https?:\/\//i.test(raw)) return true;
      if (/(-?\d{1,2}\.\d+)\s*,\s*(-?\d{1,3}\.\d+)/.test(raw)) return true;
      return raw.length >= 5;
    };

    const missing: string[] = [];

    const requiresAmountsAndLocation =
      nextPhase === ServicePhaseType.INSTALACION ||
      nextPhase === ServicePhaseType.MANTENIMIENTO ||
      nextPhase === ServicePhaseType.LEVANTAMIENTO;

    if (requiresAmountsAndLocation) {
      const quoted = extractMoney((service as any).quotedAmount);
      if (!quoted || quoted <= 0) missing.push('Monto cotizado (quotedAmount)');
      if (!finalCost || finalCost <= 0) missing.push('Monto total (orderExtras.finalCost)');
      if (!locationOk(locationText)) missing.push('Ubicación (dirección / GPS / Maps)');

      if (missing.length > 0) {
        throw new BadRequestException({
          message: missing.map((m) => `Falta: ${m}`),
          code: 'PHASE_VALIDATION',
        });
      }
    }

    if (nextPhase === ServicePhaseType.GARANTIA) {
      const isFinalized =
        service.orderState === OrderState.FINALIZED ||
        service.status === ServiceStatus.COMPLETED ||
        service.status === ServiceStatus.CLOSED;

      if (!isFinalized) {
        throw new BadRequestException({
          message: [
            'Primero finaliza la orden y luego cambia a Garantía.',
            'No puedes marcar Garantía si la orden no está FINALIZADA.',
          ],
          code: 'PHASE_WARRANTY_STATE',
        });
      }

      const hasInstallThisOrder =
        (await this.prisma.servicePhaseHistory.findFirst({
          where: {
            serviceId: id,
            OR: [{ phase: ServicePhaseType.INSTALACION }, { toPhase: ServicePhaseType.INSTALACION }],
          },
          select: { id: true },
        })) != null;

      let ok = hasInstallThisOrder;
      if (!ok) {
        const prior = await this.prisma.service.findFirst({
          where: {
            isDeleted: false,
            id: { not: id },
            customerId: service.customerId,
            category: service.category,
            AND: [
              {
                OR: [
                  { orderState: OrderState.FINALIZED },
                  { status: ServiceStatus.COMPLETED },
                  { status: ServiceStatus.CLOSED },
                ],
              },
              {
                OR: [
                  { currentPhase: ServicePhaseType.INSTALACION },
                  {
                    phaseHistory: {
                      some: {
                        OR: [
                          { phase: ServicePhaseType.INSTALACION },
                          { toPhase: ServicePhaseType.INSTALACION },
                        ],
                      },
                    },
                  },
                ],
              },
            ],
          },
          select: { id: true },
        });
        ok = prior != null;
      }

      if (!ok) {
        throw new BadRequestException({
          message: ['No puedes marcar Garantía sin una instalación finalizada del cliente.'],
          code: 'PHASE_WARRANTY_INSTALL',
        });
      }
    }

    if (nextPhase === ServicePhaseType.INSTALACION || nextPhase === ServicePhaseType.MANTENIMIENTO) {
      await this.serviceClosing.ensureDraftOnPhaseEntry({ serviceId: id, triggeredByUserId: user.id });
    }

    const durationMs =
      service.scheduledStart && service.scheduledEnd
        ? Math.max(15 * 60 * 1000, service.scheduledEnd.getTime() - service.scheduledStart.getTime())
        : 60 * 60 * 1000;

    const nextEnd = new Date(scheduledAt.getTime() + durationMs);

    const updated = await this.prisma.$transaction(async (tx) => {
      const row = await tx.service.update({
        where: { id },
        data: {
          currentPhase: nextPhase,
          scheduledStart: scheduledAt,
          scheduledEnd: nextEnd,
        },
        include: this.serviceInclude(),
      });

      await tx.servicePhaseHistory.create({
        data: {
          serviceId: id,
          phase: nextPhase,
          note: dto.note?.trim() || null,
          changedByUserId: user.id,
          fromPhase: service.currentPhase,
          toPhase: nextPhase,
        },
      });

      await tx.client.update({
        where: { id: service.customerId },
        data: { lastActivityAt: row.updatedAt },
      });

      return row;
    });

    const normalized = this.normalizeService(updated);
    try {
      this.realtime.emitServiceEvent({
        type: 'service.phase_changed',
        service: normalized,
        actorUserId: user.id,
      });
    } catch {
      // ignore
    }

    await this.invalidateOperationsCache('service.changePhase');

    return normalized;
  }

  async changeAdminPhase(user: AuthUser, id: string, dto: ChangeServiceAdminPhaseDto) {
    const service = await this.prisma.service.findFirst({
      where: { id, isDeleted: false },
      include: { assignments: true },
    });

    if (!service) throw new NotFoundException('Servicio no encontrado');
    this.assertCanOperate(user, service.createdByUserId, service.assignments.map((a) => a.userId));

    const next = this.parseAdminPhase(dto.adminPhase);

    try {
      this.assertAdminPhaseTransition({
        orderType: service.orderType,
        current: service.adminPhase,
        next,
      });
    } catch (e) {
      // In case DB is not migrated and adminPhase is missing, keep consistent error.
      if (e instanceof BadRequestException) throw e;
      throw e;
    }

    let updated: any;
    try {
      updated = await this.prisma.service.update({
        where: { id },
        data: { adminPhase: next },
        include: this.serviceInclude(),
      });
    } catch (error) {
      if (!this.isSchemaMismatch(error)) throw error;
      throw new ServiceUnavailableException('La base de datos no está migrada para adminPhase/adminStatus');
    }

    const message = (dto.message ?? '').trim();
    if (message) {
      try {
        await this.prisma.serviceUpdate.create({
          data: {
            serviceId: id,
            changedByUserId: user.id,
            type: ServiceUpdateType.NOTE,
            oldValue: Prisma.DbNull,
            newValue: { adminPhase: this.toApiAdminPhase(next) },
            message,
          },
        });
      } catch {
        // ignore
      }
    }

    const normalized = this.normalizeService(updated);
    try {
      this.realtime.emitServiceEvent({
        type: 'service.admin_phase_changed',
        service: normalized,
        actorUserId: user.id,
      });
    } catch {
      // ignore
    }

    await this.invalidateOperationsCache('service.changeAdminPhase');

    return normalized;
  }

  async changeAdminStatus(user: AuthUser, id: string, dto: ChangeServiceAdminStatusDto) {
    const service = await this.prisma.service.findFirst({
      where: { id, isDeleted: false },
      include: { assignments: true },
    });

    if (!service) throw new NotFoundException('Servicio no encontrado');
    this.assertCanOperate(user, service.createdByUserId, service.assignments.map((a) => a.userId));

    const next = this.parseAdminStatus(dto.adminStatus);

    let updated: any;
    try {
      updated = await this.prisma.service.update({
        where: { id },
        data: { adminStatus: next },
        include: this.serviceInclude(),
      });
    } catch (error) {
      if (!this.isSchemaMismatch(error)) throw error;
      throw new ServiceUnavailableException('La base de datos no está migrada para adminPhase/adminStatus');
    }

    const message = (dto.message ?? '').trim();
    if (message) {
      try {
        await this.prisma.serviceUpdate.create({
          data: {
            serviceId: id,
            changedByUserId: user.id,
            type: ServiceUpdateType.NOTE,
            oldValue: Prisma.DbNull,
            newValue: { adminStatus: this.toApiAdminStatus(next) },
            message,
          },
        });
      } catch {
        // ignore
      }
    }

    const normalized = this.normalizeService(updated);
    try {
      this.realtime.emitServiceEvent({
        type: 'service.admin_status_changed',
        service: normalized,
        actorUserId: user.id,
      });
    } catch {
      // ignore
    }

    await this.invalidateOperationsCache('service.changeAdminStatus');

    return normalized;
  }

  async listPhases(user: AuthUser, id: string) {
    const service = await this.prisma.service.findFirst({
      where: { id, isDeleted: false },
      include: { assignments: true },
    });

    if (!service) throw new NotFoundException('Servicio no encontrado');
    const techViewAll = user.role === Role.TECNICO ? await this.techCanViewAllServices() : false;
    this.assertCanView(
      user,
      service.createdByUserId,
      service.assignments.map((a) => a.userId),
      techViewAll,
    );

    const history = await this.prisma.servicePhaseHistory.findMany({
      where: { serviceId: id },
      include: {
        changedBy: { select: { id: true, nombreCompleto: true, role: true } },
      },
      orderBy: { changedAt: 'desc' },
    });

    return history.map((item) => ({
      ...item,
      phase: this.toApiPhase(item.phase),
      fromPhase: item.fromPhase ? this.toApiPhase(item.fromPhase) : null,
      toPhase: item.toPhase ? this.toApiPhase(item.toPhase) : null,
    }));
  }

  async update(user: AuthUser, id: string, dto: UpdateServiceDto) {
    const service = await this.prisma.service.findFirst({
      where: { id, isDeleted: false },
      include: { assignments: true },
    });

    if (!service) throw new NotFoundException('Servicio no encontrado');

    // Editar: solo creador o admin-like.
    this.assertCanCritical(user, service.createdByUserId);

    let technicianId: string | null | undefined = undefined;
    if (dto.technicianId !== undefined) {
      if (!dto.technicianId) {
        technicianId = null;
      } else {
        const tech = await this.prisma.user.findFirst({
          where: { id: dto.technicianId, role: Role.TECNICO, blocked: false },
          select: { id: true },
        });
        if (!tech) throw new BadRequestException('Técnico inválido');
        technicianId = tech.id;
      }
    }

    const hasCategoryChange = dto.categoryId !== undefined || dto.category !== undefined;
    const category = hasCategoryChange
      ? await this.resolveServiceCategory({
          categoryId: dto.categoryId,
          category: dto.category,
        })
      : null;
    if (hasCategoryChange && !category) {
      throw new BadRequestException('La categoría es requerida');
    }

    const data: Prisma.ServiceUpdateInput = {
      ...(dto.serviceType ? { serviceType: this.parseType(dto.serviceType) } : {}),
      ...(category
        ? {
            category: category.code,
            categoryRef: { connect: { id: category.id } },
          }
        : {}),
      ...(dto.priority != null ? { priority: dto.priority } : {}),
      ...(dto.title ? { title: dto.title.trim() } : {}),
      ...(dto.description ? { description: dto.description.trim() } : {}),
      ...(dto.quotedAmount != null ? { quotedAmount: dto.quotedAmount } : {}),
      ...(dto.depositAmount != null ? { depositAmount: dto.depositAmount } : {}),
      ...(dto.addressSnapshot !== undefined
        ? { addressSnapshot: dto.addressSnapshot?.trim() || null }
        : {}),
      ...(dto.orderType ? { orderType: this.parseOrderType(dto.orderType) } : {}),
      ...(dto.orderState ? { orderState: this.parseOrderState(dto.orderState) } : {}),
      ...(technicianId !== undefined
        ? technicianId
          ? { technician: { connect: { id: technicianId } } }
          : { technician: { disconnect: true } }
        : {}),
      ...(dto.tags ? { tags: dto.tags } : {}),
    };

    if (Object.keys(data).length === 0) {
      throw new BadRequestException('No hay cambios para guardar');
    }

    const updated = await this.prisma.service.update({
      where: { id },
      data,
      include: this.serviceInclude(),
    });

    // Best-effort: keep invoice/guarantee drafts in sync while pending.
    try {
      const touchesClosing =
        dto.serviceType !== undefined ||
        dto.title !== undefined ||
        dto.description !== undefined ||
        dto.quotedAmount !== undefined ||
        dto.addressSnapshot !== undefined ||
        dto.technicianId !== undefined;
      if (touchesClosing) {
        void this.serviceClosing.refreshDraftIfPending({ serviceId: id, triggeredByUserId: user.id }).catch(() => {
          // ignore
        });
      }
    } catch {
      // ignore
    }

    await this.prisma.client.update({
      where: { id: service.customerId },
      data: { lastActivityAt: updated.updatedAt },
    });

    const normalized = this.normalizeService(updated);
    try {
      this.realtime.emitServiceEvent({
        type: 'service.updated',
        service: normalized,
        actorUserId: user.id,
      });
    } catch {
      // ignore
    }

    await this.invalidateOperationsCache('service.update');

    return normalized;
  }

  async changeStatus(user: AuthUser, id: string, dto: ChangeServiceStatusDto) {
    const service = await this.prisma.service.findFirst({
      where: { id, isDeleted: false },
      include: {
        assignments: true,
      },
    });

    if (!service) throw new NotFoundException('Servicio no encontrado');
    const nextStatus = this.parseStatus(dto.status);

    if (nextStatus === ServiceStatus.CANCELLED) {
      this.assertCanCritical(user, service.createdByUserId);
    } else {
      this.assertCanOperate(user, service.createdByUserId, service.assignments.map((a) => a.userId));
    }

    const force = Boolean(dto.force) && this.canForce(user);

    if (!force && !this.isValidTransition(service.status, nextStatus)) {
      throw new BadRequestException(`Transición inválida de ${this.toApiStatus(service.status)} a ${dto.status}`);
    }

    if (nextStatus === ServiceStatus.COMPLETED && !force) {
      if (!service.completedAt && !service.scheduledStart) {
        throw new BadRequestException('No se puede completar sin agendado previo');
      }
    }

    const updated = await this.prisma.$transaction(async (tx) => {
      const row = await tx.service.update({
        where: { id },
        data: {
          status: nextStatus,
          completedAt: nextStatus === ServiceStatus.COMPLETED ? new Date() : service.completedAt,
        },
        include: this.serviceInclude(),
      });

      await tx.serviceUpdate.create({
        data: {
          serviceId: id,
          changedByUserId: user.id,
          type: ServiceUpdateType.STATUS_CHANGE,
          oldValue: { status: this.toApiStatus(service.status) },
          newValue: { status: dto.status, force },
          message: dto.message?.trim() || (force ? 'Cambio forzado por administrador' : 'Cambio de estado'),
        },
      });

      await tx.client.update({
        where: { id: service.customerId },
        data: { lastActivityAt: row.updatedAt },
      });

      return row;
    });

    // Notify creator + admins + assistants by fleet number when an installation is finalized.
    try {
      const isInstallation =
        service.serviceType === ServiceType.INSTALLATION ||
        service.currentPhase === ServicePhaseType.INSTALACION;
      if (nextStatus === ServiceStatus.COMPLETED && isInstallation) {
        const customerName = (updated.customer?.nombre ?? 'Cliente').toString().trim() || 'Cliente';
        const actor = await this.prisma.user
          .findUnique({ where: { id: user.id }, select: { nombreCompleto: true } })
          .catch(() => null);
        const actorName = (actor?.nombreCompleto ?? '').toString().trim();

        const lines = [
          '*Instalación finalizada*',
          `Servicio: ${(updated.title ?? '').toString().trim() || 'Servicio'}`,
          `Cliente: ${customerName}`,
          actorName ? `Marcado por: ${actorName}` : null,
          dto.message?.trim() ? `Nota: ${dto.message.trim()}` : null,
        ].filter(Boolean) as string[];

        await this.notifyFleetNumbersForService({
          serviceId: updated.id,
          createdByUserId: updated.createdByUserId,
          messageText: lines.join('\n'),
          payload: { kind: 'installation_finalized', actorUserId: user.id },
        });
      }
    } catch {
      // ignore
    }

    // Start automated service closing workflow when marking as completed.
    try {
      if (nextStatus === ServiceStatus.COMPLETED) {
        void this.serviceClosing
          .tryStartOnServiceFinalized({ serviceId: id, triggeredByUserId: user.id })
          .catch(() => {
            // ignore
          });
      }
    } catch {
      // ignore
    }

    // Best-effort internal notification (WhatsApp via Evolution)
    try {
      const important =
        nextStatus === ServiceStatus.IN_PROGRESS ||
        nextStatus === ServiceStatus.COMPLETED ||
        nextStatus === ServiceStatus.CANCELLED;

      if (important) {
        const payload = {
          template: 'service_status_changed' as const,
          data: {
            serviceId: updated.id,
            serviceTitle: updated.title,
            oldStatus: this.toApiStatus(service.status),
            newStatus: dto.status,
            note: dto.message?.trim() || null,
          },
        };

        const updatedAtIso = updated.updatedAt?.toISOString?.() ?? new Date().toISOString();
        const recipients = new Set<string>();
        if (updated.createdByUserId) recipients.add(updated.createdByUserId);
        for (const a of updated.assignments ?? []) {
          if (a?.userId) recipients.add(a.userId);
        }

        for (const recipientUserId of recipients) {
          void this.notifications
            .enqueueWhatsAppToUser({
              recipientUserId,
              payload,
              dedupeKey: `service_status_changed:${updated.id}:${recipientUserId}:${updatedAtIso}`,
            })
            .catch(() => {
              // ignore
            });
        }
      }
    } catch {
      // ignore
    }

    const normalized = this.normalizeService(updated);
    try {
      this.realtime.emitServiceEvent({
        type: 'service.status_changed',
        service: normalized,
        actorUserId: user.id,
      });
    } catch {
      // ignore
    }

    await this.invalidateOperationsCache('service.changeStatus');

    return normalized;
  }

  async changeOrderState(user: AuthUser, id: string, dto: ChangeServiceOrderStateDto) {
    const service = await this.prisma.service.findFirst({
      where: { id, isDeleted: false },
      include: { assignments: true },
    });

    if (!service) throw new NotFoundException('Servicio no encontrado');
    this.assertCanOperate(user, service.createdByUserId, service.assignments.map((a) => a.userId));

    const nextOrderState = this.parseOrderState(dto.orderState);
    const updated = await this.prisma.service.update({
      where: { id },
      data: { orderState: nextOrderState },
      include: this.serviceInclude(),
    });

    // Notify creator + admins + assistants by fleet number when an installation is finalized.
    try {
      const isInstallation =
        service.serviceType === ServiceType.INSTALLATION ||
        service.currentPhase === ServicePhaseType.INSTALACION;
      if (nextOrderState === OrderState.FINALIZED && isInstallation) {
        const customerName = (updated.customer?.nombre ?? 'Cliente').toString().trim() || 'Cliente';
        const actor = await this.prisma.user
          .findUnique({ where: { id: user.id }, select: { nombreCompleto: true } })
          .catch(() => null);
        const actorName = (actor?.nombreCompleto ?? '').toString().trim();

        const lines = [
          '*Instalación finalizada*',
          `Servicio: ${(updated.title ?? '').toString().trim() || 'Servicio'}`,
          `Cliente: ${customerName}`,
          actorName ? `Marcado por: ${actorName}` : null,
        ].filter(Boolean) as string[];

        await this.notifyFleetNumbersForService({
          serviceId: updated.id,
          createdByUserId: updated.createdByUserId,
          messageText: lines.join('\n'),
          payload: { kind: 'installation_finalized', actorUserId: user.id },
        });
      }
    } catch {
      // ignore
    }

    // Also trigger closing workflow when order is marked FINALIZED.
    try {
      if (nextOrderState === OrderState.FINALIZED) {
        void this.serviceClosing
          .tryStartOnServiceFinalized({ serviceId: id, triggeredByUserId: user.id })
          .catch(() => {
            // ignore
          });
      }
    } catch {
      // ignore
    }

    await this.prisma.client.update({
      where: { id: service.customerId },
      data: { lastActivityAt: updated.updatedAt },
    });

    const normalized = this.normalizeService(updated);
    try {
      this.realtime.emitServiceEvent({
        type: 'service.updated',
        service: normalized,
        actorUserId: user.id,
      });
    } catch {
      // ignore
    }

    await this.invalidateOperationsCache('service.changeOrderState');

    return normalized;
  }

  async schedule(user: AuthUser, id: string, dto: ScheduleServiceDto) {
    const service = await this.prisma.service.findFirst({
      where: { id, isDeleted: false },
      include: { assignments: true },
    });
    if (!service) throw new NotFoundException('Servicio no encontrado');

    this.assertCanOperate(user, service.createdByUserId, service.assignments.map((a) => a.userId));

    const start = new Date(dto.scheduledStart);
    const end = new Date(dto.scheduledEnd);
    if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime()) || end <= start) {
      throw new BadRequestException('Rango de agenda inválido');
    }

    const assignments = await this.prisma.serviceAssignment.findMany({ where: { serviceId: id } });
    const techIds = assignments.map((item) => item.userId);

    const conflicts = techIds.length
      ? await this.prisma.service.findMany({
          where: {
            id: { not: id },
            isDeleted: false,
            status: { in: [ServiceStatus.SCHEDULED, ServiceStatus.IN_PROGRESS] },
            assignments: { some: { userId: { in: techIds } } },
            scheduledStart: { lt: end },
            scheduledEnd: { gt: start },
          },
          select: { id: true, serviceType: true, title: true, scheduledStart: true, scheduledEnd: true },
        })
      : [];

    const hasInstallConflict = conflicts.some((c) => c.serviceType === ServiceType.INSTALLATION);
    if (service.serviceType !== ServiceType.INSTALLATION && hasInstallConflict) {
      throw new BadRequestException('Conflicto: existe instalación prioritaria en ese horario');
    }

    const updated = await this.prisma.$transaction(async (tx) => {
      const row = await tx.service.update({
        where: { id },
        data: {
          scheduledStart: start,
          scheduledEnd: end,
          status: service.status === ServiceStatus.RESERVED ? ServiceStatus.SCHEDULED : service.status,
        },
        include: this.serviceInclude(),
      });

      await tx.serviceUpdate.create({
        data: {
          serviceId: id,
          changedByUserId: user.id,
          type: ServiceUpdateType.SCHEDULE_CHANGE,
          oldValue: {
            scheduledStart: service.scheduledStart?.toISOString() ?? null,
            scheduledEnd: service.scheduledEnd?.toISOString() ?? null,
          },
          newValue: {
            scheduledStart: start.toISOString(),
            scheduledEnd: end.toISOString(),
            conflicts: conflicts.map((c) => c.id),
          },
          message: dto.message?.trim() || (conflicts.length ? 'Reagenda con conflictos detectados' : 'Agenda actualizada'),
        },
      });

      await tx.client.update({
        where: { id: service.customerId },
        data: { lastActivityAt: row.updatedAt },
      });

      return row;
    });

    // Best-effort reminder: when a reservation reaches its scheduled datetime,
    // notify the creator's fleet number via WhatsApp with customer details and a wa.me link.
    try {
      const isReservation = updated.currentPhase === ServicePhaseType.RESERVA;
      const isActiveStatus =
        updated.status !== ServiceStatus.CANCELLED &&
        updated.status !== ServiceStatus.CLOSED &&
        updated.status !== ServiceStatus.COMPLETED;
      if (isReservation && isActiveStatus) {
        const creator = await this.prisma.user.findUnique({
          where: { id: service.createdByUserId },
          select: { id: true, blocked: true, numeroFlota: true },
        });

        const fleetNumber = (creator?.numeroFlota ?? '').toString().trim();
        if (creator && !creator.blocked && fleetNumber) {
          const normalizeForWaMe = (raw: string) => {
            let input = (raw ?? '').toString().trim();
            if (!input) return '';

            const waMeMatch = /wa\.me\/([0-9]+)/i.exec(input);
            if (waMeMatch?.[1]) input = waMeMatch[1];

            input = input.replace(/(@c\.us|@s\.whatsapp\.net)$/i, '');

            let digits = input.replace(/[^0-9]/g, '');
            if (!digits) return '';

            if (digits.startsWith('00')) {
              digits = digits.replace(/^00+/, '');
              if (!digits) return '';
            }

            const isDominicanLocal = digits.length === 10 && /^(809|829|849)/.test(digits);
            if (isDominicanLocal) return `1${digits}`;

            if (digits.length === 11 && digits.startsWith('1')) return digits;

            return digits;
          };

          const pad2 = (n: number) => String(n).padStart(2, '0');
          const fmtLocal = (d: Date) => {
            const yyyy = d.getFullYear();
            const mm = pad2(d.getMonth() + 1);
            const dd = pad2(d.getDate());
            const hh = pad2(d.getHours());
            const min = pad2(d.getMinutes());
            return `${yyyy}-${mm}-${dd} ${hh}:${min}`;
          };

          const customerName = (updated.customer?.nombre ?? 'Cliente').toString().trim() || 'Cliente';
          const customerPhoneRaw = (updated.customer?.telefono ?? '').toString().trim();
          const customerDigits = normalizeForWaMe(customerPhoneRaw);

          const serviceTitle = (updated.title ?? '').toString().trim() || 'Reserva';
          const serviceDetail = (updated.description ?? '').toString().trim();
          const whenText = fmtLocal(start);

          const customerPrefill = [
            `Hola ${customerName},`,
            `le escribo para confirmar su cita de ${serviceTitle}.`,
            `Fecha/hora: ${whenText}.`,
            '¿Le queda bien ese horario?',
            'Gracias.',
          ].join(' ');

          const waLink = customerDigits
            ? `https://wa.me/${customerDigits}?text=${encodeURIComponent(customerPrefill)}`
            : '';

          const messageLines = [
            '*Recordatorio de reserva*',
            `Servicio: ${serviceTitle}`,
            serviceDetail ? `Detalle: ${serviceDetail}` : null,
            `Cliente: ${customerName}`,
            customerPhoneRaw ? `Teléfono: ${customerPhoneRaw}` : 'Teléfono: (no registrado)',
            `Agenda: ${whenText}`,
            waLink ? `WhatsApp cliente: ${waLink}` : 'WhatsApp cliente: (teléfono inválido)',
            'Por favor confirmar con el cliente. Avisar en la app cualquier detalle.',
          ].filter(Boolean) as string[];

          const messageText = messageLines.join('\n');

          void this.notifications
            .upsertWhatsAppRawTextScheduled({
              dedupeKey: `reservation_reminder_initial:${updated.id}`,
              toNumber: fleetNumber,
              messageText,
              nextAttemptAt: start,
              payload: {
                kind: 'reservation_reminder',
                serviceId: updated.id,
                sequence: 1,
                scheduledStart: start.toISOString(),
                scheduledEnd: end.toISOString(),
                customerName,
                customerPhone: customerPhoneRaw || null,
                customerWaMe: waLink || null,
              },
              recipientUserId: creator.id,
            })
            .catch(() => {
              // ignore
            });
        }
      }
    } catch {
      // ignore
    }

    const normalized = this.normalizeService(updated);
    try {
      this.realtime.emitServiceEvent({
        type: 'service.scheduled',
        service: normalized,
        actorUserId: user.id,
      });
    } catch {
      // ignore
    }

    await this.invalidateOperationsCache('service.schedule');

    return {
      ...normalized,
      conflicts: conflicts.map((c) => ({
        id: c.id,
        type: this.toApiType(c.serviceType),
        title: c.title,
        scheduledStart: c.scheduledStart,
        scheduledEnd: c.scheduledEnd,
      })),
    };
  }

  async assign(user: AuthUser, id: string, dto: AssignServiceDto) {
    const service = await this.prisma.service.findFirst({
      where: { id, isDeleted: false },
      include: { assignments: true },
    });
    if (!service) throw new NotFoundException('Servicio no encontrado');

    this.assertCanOperate(user, service.createdByUserId, service.assignments.map((a) => a.userId));

    const techIds = dto.assignments.map((item) => item.userId);
    const users = await this.prisma.user.findMany({
      where: { id: { in: techIds }, role: { in: [Role.TECNICO, Role.ADMIN, Role.ASISTENTE] }, blocked: false },
      select: { id: true },
    });

    if (users.length !== techIds.length) {
      throw new BadRequestException('Hay técnicos inválidos en la asignación');
    }

    const oldAssignments = service.assignments.map((item) => ({ userId: item.userId, role: this.toApiAssignRole(item.role) }));

    const updated = await this.prisma.$transaction(async (tx) => {
      await tx.serviceAssignment.deleteMany({ where: { serviceId: id } });
      await tx.serviceAssignment.createMany({
        data: dto.assignments.map((item) => ({
          serviceId: id,
          userId: item.userId,
          role: this.parseAssignRole(item.role),
        })),
      });

      const lead = dto.assignments.find((a) => a.role === 'lead') ?? dto.assignments[0];
      const leadId = lead?.userId ?? null;
      try {
        await tx.service.update({
          where: { id },
          data: { technicianId: leadId },
        });
      } catch (error) {
        if (!this.isSchemaMismatch(error)) throw error;
      }

      await tx.serviceUpdate.create({
        data: {
          serviceId: id,
          changedByUserId: user.id,
          type: ServiceUpdateType.ASSIGNMENT_CHANGE,
          oldValue: oldAssignments as Prisma.InputJsonValue,
          newValue: dto.assignments as unknown as Prisma.InputJsonValue,
          message: 'Asignaciones actualizadas',
        },
      });

      await tx.client.update({
        where: { id: service.customerId },
        data: { lastActivityAt: new Date() },
      });

      return tx.service.findUnique({ where: { id }, include: this.serviceInclude() });
    });

    if (!updated) throw new NotFoundException('Servicio no encontrado');

    // Best-effort internal notification (WhatsApp via Evolution)
    try {
      const normalized = this.normalizeService(updated);
      const rawAddress =
        (updated.addressSnapshot ?? updated.customer?.direccion ?? '')
          ?.toString?.()
          ?.trim?.() ?? '';
      const payload = {
        template: 'service_assigned' as const,
        data: {
          serviceId: normalized.id,
          serviceTitle: normalized.title,
          customerName: normalized.customer?.nombre ?? 'Cliente',
          customerPhone: normalized.customer?.telefono ?? null,
          address: rawAddress.length ? rawAddress : null,
          scheduledStart: updated.scheduledStart
            ? updated.scheduledStart.toISOString()
            : null,
          scheduledEnd: updated.scheduledEnd ? updated.scheduledEnd.toISOString() : null,
        },
      };

      const updatedAtIso = updated.updatedAt?.toISOString?.() ?? new Date().toISOString();
      const recipientIds = Array.from(
        new Set((dto.assignments ?? []).map((a) => a.userId).filter(Boolean)),
      );

      for (const recipientUserId of recipientIds) {
        void this.notifications
          .enqueueWhatsAppToUser({
            recipientUserId,
            payload,
            dedupeKey: `service_assigned:${updated.id}:${recipientUserId}:${updatedAtIso}`,
          })
          .catch(() => {
            // ignore
          });
      }
    } catch {
      // ignore
    }

    const normalized = this.normalizeService(updated);
    try {
      this.realtime.emitServiceEvent({
        type: 'service.assigned',
        service: normalized,
        actorUserId: user.id,
      });
    } catch {
      // ignore
    }

    await this.invalidateOperationsCache('service.assign');

    return normalized;
  }

  async addUpdate(user: AuthUser, id: string, dto: ServiceUpdateDto) {
    const service = await this.prisma.service.findFirst({
      where: { id, isDeleted: false },
      include: { assignments: true, customer: { select: { nombre: true } } },
    });
    if (!service) throw new NotFoundException('Servicio no encontrado');

    this.assertCanOperate(user, service.createdByUserId, service.assignments.map((a) => a.userId));

    let message = dto.message?.trim();

    if (dto.stepId) {
      const step = await this.prisma.serviceStep.findFirst({ where: { id: dto.stepId, serviceId: id } });
      if (!step) throw new BadRequestException('Paso no encontrado');

      const isDone = dto.stepDone === true;
      await this.prisma.serviceStep.update({
        where: { id: step.id },
        data: {
          isDone,
          doneAt: isDone ? new Date() : null,
          doneByUserId: isDone ? user.id : null,
        },
      });

      message = message || `Paso ${step.stepLabel} ${isDone ? 'completado' : 'marcado pendiente'}`;

      await this.prisma.serviceUpdate.create({
        data: {
          serviceId: id,
          changedByUserId: user.id,
          type: ServiceUpdateType.STEP_UPDATE,
          oldValue: { stepId: step.id, isDone: step.isDone },
          newValue: { stepId: step.id, isDone },
          message,
        },
      });

      await this.prisma.client.update({
        where: { id: service.customerId },
        data: { lastActivityAt: new Date() },
      });

      // Notify creator + admins + assistants by fleet number on step updates.
      try {
        const actor = await this.prisma.user
          .findUnique({ where: { id: user.id }, select: { nombreCompleto: true } })
          .catch(() => null);
        const actorName = (actor?.nombreCompleto ?? '').toString().trim();

        const customerName = (service.customer?.nombre ?? 'Cliente').toString().trim() || 'Cliente';
        const lines = [
          '*Novedad registrada*',
          'Tipo: Paso',
          `Servicio: ${(service.title ?? '').toString().trim() || 'Servicio'}`,
          `Cliente: ${customerName}`,
          actorName ? `Por: ${actorName}` : null,
          `Detalle: ${message}`,
        ].filter(Boolean) as string[];

        await this.notifyFleetNumbersForService({
          serviceId: id,
          createdByUserId: service.createdByUserId,
          messageText: lines.join('\n'),
          payload: { kind: 'service_step_update', actorUserId: user.id },
        });
      } catch {
        // ignore
      }

      const normalized = await this.findOne(user, id);
      try {
        this.realtime.emitServiceEvent({
          type: 'service.step_updated',
          service: normalized,
          actorUserId: user.id,
        });
      } catch {
        // ignore
      }

      await this.invalidateOperationsCache('service.addUpdate.step');

      return normalized;
    }

    const type = this.parseUpdateType(dto.type);
    await this.prisma.serviceUpdate.create({
      data: {
        serviceId: id,
        changedByUserId: user.id,
        type,
        oldValue: dto.oldValue ? (dto.oldValue as Prisma.InputJsonValue) : Prisma.DbNull,
        newValue: dto.newValue ? (dto.newValue as Prisma.InputJsonValue) : Prisma.DbNull,
        message: message || 'Actualización interna',
      },
    });

    await this.prisma.client.update({
      where: { id: service.customerId },
      data: { lastActivityAt: new Date() },
    });

    // Notify creator + admins + assistants by fleet number on novedades/notas/evidencias.
    try {
      const actor = await this.prisma.user
        .findUnique({ where: { id: user.id }, select: { nombreCompleto: true } })
        .catch(() => null);
      const actorName = (actor?.nombreCompleto ?? '').toString().trim();

      const customerName = (service.customer?.nombre ?? 'Cliente').toString().trim() || 'Cliente';
      const typeLabel = (() => {
        switch (type) {
          case ServiceUpdateType.NOTE:
            return 'Nota';
          case ServiceUpdateType.PAYMENT_UPDATE:
            return 'Pago/extra';
          case ServiceUpdateType.FILE_UPLOAD:
            return 'Evidencia';
          case ServiceUpdateType.STEP_UPDATE:
            return 'Paso';
          case ServiceUpdateType.SCHEDULE_CHANGE:
            return 'Agenda';
          case ServiceUpdateType.ASSIGNMENT_CHANGE:
            return 'Asignación';
          default:
            return 'Actualización';
        }
      })();

      const lines = [
        '*Novedad registrada*',
        `Tipo: ${typeLabel}`,
        `Servicio: ${(service.title ?? '').toString().trim() || 'Servicio'}`,
        `Cliente: ${customerName}`,
        actorName ? `Por: ${actorName}` : null,
        (message ?? '').toString().trim() ? `Detalle: ${(message ?? '').toString().trim()}` : null,
      ].filter(Boolean) as string[];

      await this.notifyFleetNumbersForService({
        serviceId: id,
        createdByUserId: service.createdByUserId,
        messageText: lines.join('\n'),
        payload: { kind: 'service_update', updateType: type, actorUserId: user.id },
      });
    } catch {
      // ignore
    }

    // Emit best-effort realtime snapshot so all clients update instantly.
    try {
      const normalized = await this.findOne(user, id);
      this.realtime.emitServiceEvent({
        type: 'service.updated',
        service: normalized,
        actorUserId: user.id,
      });
    } catch {
      // ignore
    }

    await this.invalidateOperationsCache('service.addUpdate');

    return { ok: true };
  }

  async getExecutionReport(user: AuthUser, serviceId: string, technicianId?: string) {
    const service = await this.prisma.service.findFirst({
      where: { id: serviceId, isDeleted: false },
      include: { assignments: true },
    });
    if (!service) throw new NotFoundException('Servicio no encontrado');

    const techViewAll = user.role === Role.TECNICO ? await this.techCanViewAllServices() : false;
    this.assertCanView(user, service.createdByUserId, service.assignments.map((a) => a.userId), techViewAll);

    const targetTechnicianId =
      user.role === Role.TECNICO
        ? user.id
        : (technicianId ?? service.technicianId ?? service.assignments?.[0]?.userId ?? '').trim();

    if (!targetTechnicianId) {
      return { report: null, changes: [] };
    }

    try {
      const report = await this.prisma.serviceExecutionReport.findFirst({
        where: { serviceId, technicianId: targetTechnicianId },
      });
      if (!report) return { report: null, changes: [] };

      const changes = await this.prisma.serviceExecutionChange.findMany({
        where: { executionReportId: report.id },
        orderBy: { createdAt: 'asc' },
      });

      return { report, changes };
    } catch (error) {
      if (this.isSchemaMismatch(error)) {
        return { report: null, changes: [] };
      }
      throw error;
    }
  }

  async upsertExecutionReport(user: AuthUser, serviceId: string, dto: UpsertExecutionReportDto) {
    const service = await this.prisma.service.findFirst({
      where: { id: serviceId, isDeleted: false },
      include: { assignments: true, customer: { select: { nombre: true } } },
    });
    if (!service) throw new NotFoundException('Servicio no encontrado');

    const assignedIds = service.assignments.map((a) => a.userId);
    this.assertCanOperate(user, service.createdByUserId, assignedIds);

    const readOnly =
      (service.status === ServiceStatus.CLOSED || service.status === ServiceStatus.CANCELLED) &&
      !this.isAdminLike(user.role);
    if (readOnly) {
      throw new ForbiddenException('Servicio finalizado: reporte en modo lectura');
    }

    const targetTechnicianId =
      user.role === Role.TECNICO ? user.id : (dto.technicianId ?? service.technicianId ?? '').trim();
    if (!targetTechnicianId) throw new BadRequestException('Falta technicianId');

    if (!this.isAdminLike(user.role) && targetTechnicianId !== user.id) {
      throw new ForbiddenException('No autorizado para guardar reporte de otro técnico');
    }

    const nextPhaseRaw = (dto.phase ?? '').trim();
    const phase = nextPhaseRaw.length ? this.parsePhase(nextPhaseRaw) : service.currentPhase;

    const arrivedAt = dto.arrivedAt ? new Date(dto.arrivedAt) : undefined;
    const startedAt = dto.startedAt ? new Date(dto.startedAt) : undefined;
    const finishedAt = dto.finishedAt ? new Date(dto.finishedAt) : undefined;

    // Best-effort: detect note changes to notify (avoid noisy re-sends).
    const prevNotes = await this.prisma.serviceExecutionReport
      .findUnique({
        where: {
          serviceId_technicianId: {
            serviceId,
            technicianId: targetTechnicianId,
          },
        },
        select: { notes: true },
      })
      .then((r) => (r?.notes ?? null))
      .catch(() => null);

    try {
      const updated = await this.prisma.serviceExecutionReport.upsert({
        where: {
          serviceId_technicianId: {
            serviceId,
            technicianId: targetTechnicianId,
          },
        },
        create: {
          serviceId,
          technicianId: targetTechnicianId,
          phase,
          arrivedAt,
          startedAt,
          finishedAt,
          notes: dto.notes?.trim() || null,
          checklistData: (dto.checklistData ?? Prisma.DbNull) as any,
          phaseSpecificData: (dto.phaseSpecificData ?? Prisma.DbNull) as any,
          clientApproved: dto.clientApproved === true,
        },
        update: {
          phase,
          ...(arrivedAt !== undefined ? { arrivedAt } : {}),
          ...(startedAt !== undefined ? { startedAt } : {}),
          ...(finishedAt !== undefined ? { finishedAt } : {}),
          ...(dto.notes != null ? { notes: dto.notes.trim() || null } : {}),
          ...(dto.checklistData !== undefined ? { checklistData: dto.checklistData as any } : {}),
          ...(dto.phaseSpecificData !== undefined
            ? { phaseSpecificData: dto.phaseSpecificData as any }
            : {}),
          ...(dto.clientApproved !== undefined
            ? { clientApproved: dto.clientApproved === true }
            : {}),
        },
      });

      const changes = await this.prisma.serviceExecutionChange.findMany({
        where: { executionReportId: updated.id },
        orderBy: { createdAt: 'asc' },
      });

      // Notify creator + admins + assistants when technician updates report notes.
      try {
        const newNotes = dto.notes != null ? dto.notes.trim() : '';
        const oldNotes = (prevNotes ?? '').toString().trim();
        if (newNotes && newNotes !== oldNotes) {
          const actor = await this.prisma.user
            .findUnique({ where: { id: user.id }, select: { nombreCompleto: true } })
            .catch(() => null);
          const actorName = (actor?.nombreCompleto ?? '').toString().trim();

          const customerName = (service.customer?.nombre ?? 'Cliente').toString().trim() || 'Cliente';
          const lines = [
            '*Nota del técnico*',
            `Servicio: ${(service.title ?? '').toString().trim() || 'Servicio'}`,
            `Cliente: ${customerName}`,
            actorName ? `Por: ${actorName}` : null,
            `Detalle: ${newNotes}`,
          ].filter(Boolean) as string[];

          await this.notifyFleetNumbersForService({
            serviceId,
            createdByUserId: service.createdByUserId,
            messageText: lines.join('\n'),
            payload: { kind: 'execution_report_note', actorUserId: user.id },
          });
        }
      } catch {
        // ignore
      }

      // Emit best-effort realtime to prompt lists/detail refresh across devices.
      try {
        const normalized = await this.findOne(user, serviceId);
        this.realtime.emitServiceEvent({
          type: 'service.execution_report_updated',
          service: normalized,
          actorUserId: user.id,
        });
      } catch {
        // ignore
      }

      return { report: updated, changes };
    } catch (error) {
      if (this.isSchemaMismatch(error)) {
        throw new ServiceUnavailableException(
          'Reporte técnico no disponible: falta aplicar migraciones en el servidor.',
        );
      }
      throw error;
    }
  }

  async addExecutionChange(user: AuthUser, serviceId: string, dto: CreateExecutionChangeDto) {
    const service = await this.prisma.service.findFirst({
      where: { id: serviceId, isDeleted: false },
      include: { assignments: true, customer: { select: { nombre: true } } },
    });
    if (!service) throw new NotFoundException('Servicio no encontrado');

    const assignedIds = service.assignments.map((a) => a.userId);
    this.assertCanOperate(user, service.createdByUserId, assignedIds);

    const readOnly =
      (service.status === ServiceStatus.CLOSED || service.status === ServiceStatus.CANCELLED) &&
      !this.isAdminLike(user.role);
    if (readOnly) {
      throw new ForbiddenException('Servicio finalizado: cambios en modo lectura');
    }

    const targetTechnicianId =
      user.role === Role.TECNICO
        ? user.id
        : (service.technicianId ?? service.assignments?.[0]?.userId ?? '').trim();
    if (!targetTechnicianId) throw new BadRequestException('Falta technicianId');

    try {
      const report = await this.prisma.serviceExecutionReport.upsert({
        where: {
          serviceId_technicianId: {
            serviceId,
            technicianId: targetTechnicianId,
          },
        },
        create: {
          serviceId,
          technicianId: targetTechnicianId,
          phase: service.currentPhase,
        },
        update: {},
      });

      const created = await this.prisma.serviceExecutionChange.create({
        data: {
          serviceId,
          executionReportId: report.id,
          createdByUserId: user.id,
          type: dto.type.trim(),
          description: dto.description.trim(),
          quantity: dto.quantity,
          extraCost: dto.extraCost,
          clientApproved: dto.clientApproved,
          note: dto.note?.trim() || null,
        },
      });

      // Best-effort: regenerate pending drafts to reflect extras.
      try {
        void this.serviceClosing.refreshDraftIfPending({ serviceId, triggeredByUserId: user.id }).catch(() => {
          // ignore
        });
      } catch {
        // ignore
      }

      // Notify creator + admins + assistants by fleet number on execution changes.
      try {
        const actor = await this.prisma.user
          .findUnique({ where: { id: user.id }, select: { nombreCompleto: true } })
          .catch(() => null);
        const actorName = (actor?.nombreCompleto ?? '').toString().trim();
        const customerName = (service.customer?.nombre ?? 'Cliente').toString().trim() || 'Cliente';

        const lines = [
          '*Novedad del técnico*',
          `Servicio: ${(service.title ?? '').toString().trim() || 'Servicio'}`,
          `Cliente: ${customerName}`,
          actorName ? `Por: ${actorName}` : null,
          `Tipo: ${dto.type.trim()}`,
          `Detalle: ${dto.description.trim()}`,
          dto.note?.trim() ? `Nota: ${dto.note.trim()}` : null,
        ].filter(Boolean) as string[];

        await this.notifyFleetNumbersForService({
          serviceId,
          createdByUserId: service.createdByUserId,
          messageText: lines.join('\n'),
          payload: { kind: 'execution_change', actorUserId: user.id },
        });
      } catch {
        // ignore
      }

      // Emit best-effort realtime snapshot so everyone sees the change.
      try {
        const normalized = await this.findOne(user, serviceId);
        this.realtime.emitServiceEvent({
          type: 'service.execution_change_added',
          service: normalized,
          actorUserId: user.id,
        });
      } catch {
        // ignore
      }

      return created;
    } catch (error) {
      if (this.isSchemaMismatch(error)) {
        throw new ServiceUnavailableException(
          'Cambios del reporte técnico no disponibles: falta aplicar migraciones en el servidor.',
        );
      }
      throw error;
    }
  }

  async deleteExecutionChange(user: AuthUser, serviceId: string, changeId: string) {
    const service = await this.prisma.service.findFirst({
      where: { id: serviceId, isDeleted: false },
      include: { assignments: true },
    });
    if (!service) throw new NotFoundException('Servicio no encontrado');

    const assignedIds = service.assignments.map((a) => a.userId);
    this.assertCanOperate(user, service.createdByUserId, assignedIds);

    try {
      const change = await this.prisma.serviceExecutionChange.findFirst({
        where: { id: changeId, serviceId },
      });
      if (!change) throw new NotFoundException('Cambio no encontrado');

      const isOwner = change.createdByUserId === user.id;
      if (!isOwner && !this.isAdminLike(user.role)) {
        throw new ForbiddenException('No autorizado para eliminar este cambio');
      }

      await this.prisma.serviceExecutionChange.delete({ where: { id: changeId } });

      // Best-effort: regenerate pending drafts to reflect extras.
      try {
        void this.serviceClosing.refreshDraftIfPending({ serviceId, triggeredByUserId: user.id }).catch(() => {
          // ignore
        });
      } catch {
        // ignore
      }

      // Emit best-effort realtime snapshot so everyone sees the change.
      try {
        const normalized = await this.findOne(user, serviceId);
        this.realtime.emitServiceEvent({
          type: 'service.execution_change_deleted',
          service: normalized,
          actorUserId: user.id,
        });
      } catch {
        // ignore
      }

      return { ok: true };
    } catch (error) {
      if (this.isSchemaMismatch(error)) {
        throw new ServiceUnavailableException(
          'Cambios del reporte técnico no disponibles: falta aplicar migraciones en el servidor.',
        );
      }
      throw error;
    }
  }

  async addFile(user: AuthUser, id: string, fileUrl: string, fileType: string) {
    const service = await this.prisma.service.findFirst({
      where: { id, isDeleted: false },
      include: { assignments: true },
    });
    if (!service) throw new NotFoundException('Servicio no encontrado');

    this.assertCanOperate(user, service.createdByUserId, service.assignments.map((a) => a.userId));

    const file = await this.prisma.$transaction(async (tx) => {
      const row = await tx.serviceFile.create({
        data: {
          serviceId: id,
          uploadedByUserId: user.id,
          fileUrl,
          fileType,
        },
      });

      await tx.serviceUpdate.create({
        data: {
          serviceId: id,
          changedByUserId: user.id,
          type: ServiceUpdateType.FILE_UPLOAD,
          oldValue: Prisma.DbNull,
          newValue: { fileUrl, fileType },
          message: 'Evidencia subida',
        },
      });

      await tx.client.update({
        where: { id: service.customerId },
        data: { lastActivityAt: new Date() },
      });

      return row;
    });

    // Notify creator + admins + assistants by fleet number when evidence is uploaded.
    try {
      const hydrated = await this.prisma.service
        .findFirst({ where: { id, isDeleted: false }, include: { customer: { select: { nombre: true } } } })
        .catch(() => null);
      if (hydrated) {
        const actor = await this.prisma.user
          .findUnique({ where: { id: user.id }, select: { nombreCompleto: true } })
          .catch(() => null);
        const actorName = (actor?.nombreCompleto ?? '').toString().trim();
        const customerName = (hydrated.customer?.nombre ?? 'Cliente').toString().trim() || 'Cliente';

        const lines = [
          '*Evidencia subida*',
          `Servicio: ${(hydrated.title ?? '').toString().trim() || 'Servicio'}`,
          `Cliente: ${customerName}`,
          actorName ? `Por: ${actorName}` : null,
          fileType?.trim() ? `Tipo: ${fileType.trim()}` : null,
        ].filter(Boolean) as string[];

        await this.notifyFleetNumbersForService({
          serviceId: id,
          createdByUserId: hydrated.createdByUserId,
          messageText: lines.join('\n'),
          payload: { kind: 'file_upload', actorUserId: user.id },
        });
      }
    } catch {
      // ignore
    }

    await this.invalidateOperationsCache('service.addFile');

    return file;
  }

  async createWarranty(user: AuthUser, parentId: string, dto: CreateWarrantyDto) {
    const parent = await this.prisma.service.findFirst({
      where: { id: parentId, isDeleted: false },
      include: { assignments: true },
    });
    if (!parent) throw new NotFoundException('Servicio no encontrado');

    this.assertCanOperate(user, parent.createdByUserId, parent.assignments.map((a) => a.userId));

    if (parent.status !== ServiceStatus.COMPLETED && parent.status !== ServiceStatus.WARRANTY && parent.status !== ServiceStatus.CLOSED) {
      throw new BadRequestException('Solo se puede crear garantía desde servicio completado/cerrado');
    }

    const category = await this.resolveServiceCategory({
      categoryId: parent.categoryId,
      category: parent.category,
    });

    const created = await this.prisma.$transaction(async (tx) => {
      let row: any;
      for (let attempt = 0; attempt < 5; attempt++) {
        try {
          row = await tx.service.create({
            data: {
              customerId: parent.customerId,
              createdByUserId: user.id,
              serviceType: ServiceType.WARRANTY,
              category: category?.code ?? parent.category,
              ...(category ? { categoryRef: { connect: { id: category.id } } } : {}),
              status: ServiceStatus.WARRANTY,
              priority: 1,
              title: dto.title?.trim() || `Garantía: ${parent.title}`,
              description: dto.description?.trim() || `Garantía derivada del servicio ${parent.id}`,
              paymentStatus: 'pending',
              addressSnapshot: parent.addressSnapshot,
              warrantyParentServiceId: parent.id,
              tags: parent.tags,
              steps: { create: defaultSteps },
              orderNumber: this.generateOrderNumber(new Date()),
            } as any,
            include: this.serviceInclude(),
          });
          break;
        } catch (err) {
          if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') {
            continue;
          }
          throw err;
        }
      }
      if (!row) {
        row = await tx.service.create({
          data: {
            customerId: parent.customerId,
            createdByUserId: user.id,
            serviceType: ServiceType.WARRANTY,
            category: category?.code ?? parent.category,
            ...(category ? { categoryRef: { connect: { id: category.id } } } : {}),
            status: ServiceStatus.WARRANTY,
            priority: 1,
            title: dto.title?.trim() || `Garantía: ${parent.title}`,
            description: dto.description?.trim() || `Garantía derivada del servicio ${parent.id}`,
            paymentStatus: 'pending',
            addressSnapshot: parent.addressSnapshot,
            warrantyParentServiceId: parent.id,
            tags: parent.tags,
            steps: { create: defaultSteps },
          } as any,
          include: this.serviceInclude(),
        });
      }

      await tx.serviceUpdate.create({
        data: {
          serviceId: parent.id,
          changedByUserId: user.id,
          type: ServiceUpdateType.WARRANTY_CREATED,
          oldValue: Prisma.DbNull,
          newValue: { warrantyServiceId: row.id },
          message: 'Se creó ticket de garantía',
        },
      });

      await tx.serviceUpdate.create({
        data: {
          serviceId: row.id,
          changedByUserId: user.id,
          type: ServiceUpdateType.STATUS_CHANGE,
          oldValue: Prisma.DbNull,
          newValue: { status: 'warranty' },
          message: 'Ticket de garantía creado',
        },
      });

      return row;
    });

    const normalized = this.normalizeService(created);

    // Notify all technicians (fleet numbers) that a new warranty order was created.
    try {
      await this.notifyAllTechniciansForNewService({
        serviceId: created.id,
        createdByUserId: created.createdByUserId,
        serviceTitle: created.title,
        serviceTypeLabel: 'Garantía',
        customerName: created.customer?.nombre ?? 'Cliente',
        actorUserId: user.id,
      });
    } catch {
      // ignore
    }

    await this.invalidateOperationsCache('service.createWarranty');

    return normalized;
  }

  async remove(user: AuthUser, id: string) {
    const service = await this.prisma.service.findFirst({ where: { id, isDeleted: false } });
    if (!service) throw new NotFoundException('Servicio no encontrado');

    this.assertCanCritical(user, service.createdByUserId);

    await this.prisma.$transaction(async (tx) => {
      await tx.service.update({ where: { id }, data: { isDeleted: true } });
      await tx.serviceUpdate.create({
        data: {
          serviceId: id,
          changedByUserId: user.id,
          type: ServiceUpdateType.NOTE,
          oldValue: Prisma.DbNull,
          newValue: { isDeleted: true },
          message: 'Servicio eliminado (soft delete)',
        },
      });
    });

    await this.invalidateOperationsCache('service.remove');

    return { ok: true };
  }

  async servicesByCustomer(user: AuthUser, customerId: string) {
    const techViewAll = user.role === Role.TECNICO ? await this.techCanViewAllServices() : false;
    const items = await this.prisma.service.findMany({
      where: {
        customerId,
        isDeleted: false,
        ...this.scopeWhere(user, techViewAll),
      },
      include: this.serviceInclude(),
      orderBy: [{ createdAt: 'desc' }],
    });

    return items.map((item) => this.normalizeService(item));
  }

  async dashboard(user: AuthUser, from?: string, to?: string) {
    const techViewAll = user.role === Role.TECNICO ? await this.techCanViewAllServices() : false;
    const cacheKey = this.buildDashboardCacheKey(user, from, to, techViewAll);
    const cached = await this.redis.get<{
      activeByStatus: Array<{ status: string; count: number }>;
      installationsPendingToday: number;
      warrantiesOpen: number;
      averageHoursByLifecycle: number;
      technicianPerformance: Array<{ userId: string; technicianName: string; completedCount: number }>;
    }>(cacheKey);

    if (cached) {
      if (this.redis.isEnabled()) {
        this.logger.log(`Redis HIT ${cacheKey}`);
      }
      return cached;
    }

    if (this.redis.isEnabled()) {
      this.logger.log(`Redis MISS ${cacheKey}`);
    }

    const where: Prisma.ServiceWhereInput = {
      ...this.scopeWhere(user, techViewAll),
      isDeleted: false,
      ...this.scheduleRangeWhere(from, to),
    };

    let byStatus: Array<{ status: ServiceStatus; _count: { _all: number } }> = [];
    let installationsPendingToday = 0;
    let warrantiesOpen = 0;
    let completedByTech: Array<{ userId: string; _count: { _all: number } }> = [];
    let avgPerStage: Array<{ id: string; createdAt: Date; completedAt: Date | null }> = [];

    try {
      [byStatus, installationsPendingToday, warrantiesOpen, completedByTech, avgPerStage] = await Promise.all([
        this.prisma.service.groupBy({ by: ['status'], where, _count: { _all: true } }),
        this.prisma.service.count({
          where: {
            ...where,
            serviceType: ServiceType.INSTALLATION,
            status: { in: [ServiceStatus.RESERVED, ServiceStatus.SURVEY, ServiceStatus.SCHEDULED, ServiceStatus.IN_PROGRESS] },
            scheduledStart: { gte: this.startOfDay(), lt: this.endOfDay() },
          },
        }),
        this.prisma.service.count({ where: { ...where, status: ServiceStatus.WARRANTY } }),
        this.prisma.serviceAssignment.groupBy({
          by: ['userId'],
          where: {
            service: {
              ...where,
              status: ServiceStatus.COMPLETED,
            },
          },
          _count: { _all: true },
        }),
        this.prisma.service.findMany({
          where: { ...where, status: ServiceStatus.COMPLETED, completedAt: { not: null } },
          select: { id: true, createdAt: true, completedAt: true },
        }),
      ]);
    } catch (error) {
      if (!this.isSchemaMismatch(error)) throw error;
      byStatus = [];
      installationsPendingToday = 0;
      warrantiesOpen = 0;
      completedByTech = [];
      avgPerStage = [];
    }

    const techIds = completedByTech.map((row) => row.userId);
    let techs: Array<{ id: string; nombreCompleto: string }> = [];
    if (techIds.length) {
      try {
        techs = await this.prisma.user.findMany({ where: { id: { in: techIds } }, select: { id: true, nombreCompleto: true } });
      } catch (error) {
        if (!this.isSchemaMismatch(error)) throw error;
        techs = [];
      }
    }
    const techMap = new Map(techs.map((t) => [t.id, t.nombreCompleto]));

    const averageHours = avgPerStage.length
      ? avgPerStage.reduce((acc, row) => {
          if (!row.completedAt) return acc;
          return acc + (row.completedAt.getTime() - row.createdAt.getTime()) / (1000 * 60 * 60);
        }, 0) / avgPerStage.length
      : 0;

    const response = {
      activeByStatus: byStatus.map((row) => ({ status: this.toApiStatus(row.status), count: row._count._all })),
      installationsPendingToday,
      warrantiesOpen,
      averageHoursByLifecycle: Number(averageHours.toFixed(2)),
      technicianPerformance: completedByTech.map((row) => ({
        userId: row.userId,
        technicianName: techMap.get(row.userId) ?? 'Técnico',
        completedCount: row._count._all,
      })),
    };

    await this.redis.set(cacheKey, response, 60);

    return response;
  }

  private serviceInclude() {
    return {
      categoryRef: {
        select: {
          id: true,
          name: true,
          code: true,
        },
      },
      customer: {
        select: {
          id: true,
          nombre: true,
          telefono: true,
          direccion: true,
        },
      },
      createdBy: {
        select: { id: true, nombreCompleto: true, role: true },
      },
      assignments: {
        include: {
          user: { select: { id: true, nombreCompleto: true, role: true } },
        },
      },
      steps: {
        orderBy: { stepLabel: 'asc' as const },
      },
      updates: {
        include: {
          changedBy: { select: { id: true, nombreCompleto: true, role: true } },
        },
        orderBy: { createdAt: 'desc' as const },
      },
      files: {
        orderBy: { createdAt: 'desc' as const },
      },

      technicalVisit: true,
    };
  }

  private pad2(n: number) {
    return `${n}`.padStart(2, '0');
  }

  private pad3(n: number) {
    return `${n}`.padStart(3, '0');
  }

  private generateOrderNumber(now: Date = new Date()) {
    const yyyy = now.getFullYear();
    const MM = this.pad2(now.getMonth() + 1);
    const dd = this.pad2(now.getDate());
    const HH = this.pad2(now.getHours());
    const mm = this.pad2(now.getMinutes());
    const ss = this.pad2(now.getSeconds());
    const SSS = this.pad3(now.getMilliseconds());
    const suffix = this.pad2(Math.floor(Math.random() * 100));
    return `${yyyy}${MM}${dd}${HH}${mm}${ss}${SSS}${suffix}`;
  }

  private computeFallbackOrderNumber(params: {
    createdAt?: Date | null;
    serviceId?: string | null;
  }) {
    const createdAt = params.createdAt instanceof Date ? params.createdAt : new Date();
    const serviceId = (params.serviceId ?? '').toString();

    const yyyy = createdAt.getFullYear();
    const MM = this.pad2(createdAt.getMonth() + 1);
    const dd = this.pad2(createdAt.getDate());
    const HH = this.pad2(createdAt.getHours());
    const mm = this.pad2(createdAt.getMinutes());
    const ss = this.pad2(createdAt.getSeconds());
    const SSS = this.pad3(createdAt.getMilliseconds());

    const hexTail = serviceId.replace(/-/g, '').slice(-6);
    const tailNum = hexTail ? parseInt(hexTail, 16) : 0;
    const stableSuffix = this.pad3(Math.abs(tailNum) % 1000);

    return `${yyyy}${MM}${dd}${HH}${mm}${ss}${SSS}${stableSuffix}`;
  }

  private normalizeService(service: any) {
    const orderNumber =
      typeof service?.orderNumber === 'string' && service.orderNumber.trim()
        ? service.orderNumber.trim()
        : this.computeFallbackOrderNumber({
            createdAt: service?.createdAt,
            serviceId: service?.id,
          });
    const categoryRef = service?.categoryRef ?? null;
    const categoryCode =
      typeof categoryRef?.code === 'string' && categoryRef.code.trim()
        ? categoryRef.code.trim()
        : (service?.category ?? '').toString().trim();
    const categoryName =
      typeof categoryRef?.name === 'string' && categoryRef.name.trim()
        ? categoryRef.name.trim()
        : categoryCode;

    return {
      ...service,
      orderNumber,
      categoryId: categoryRef?.id ?? service?.categoryId ?? null,
      categoryName,
      categoryRef,
      category: categoryCode,
      serviceType: this.toApiType(service.serviceType),
      status: this.toApiStatus(service.status),
      currentPhase: service.currentPhase ? this.toApiPhase(service.currentPhase) : 'reserva',
      orderType: service.orderType ? this.toApiOrderType(service.orderType) : 'reserva',
      orderState: service.orderState ? this.toApiOrderState(service.orderState) : 'pending',
      adminPhase: service.adminPhase ? this.toApiAdminPhase(service.adminPhase) : null,
      adminStatus: service.adminStatus ? this.toApiAdminStatus(service.adminStatus) : null,
      assignments: (service.assignments ?? []).map((item: any) => ({
        ...item,
        role: this.toApiAssignRole(item.role),
      })),
      updates: (service.updates ?? []).map((item: any) => ({
        ...item,
        type: this.toApiUpdateType(item.type),
      })),
    };
  }

  private scopeWhere(user: AuthUser, techViewAll: boolean): Prisma.ServiceWhereInput {
    if (user.role === Role.ADMIN || user.role === Role.ASISTENTE) return {};
    if (user.role === Role.VENDEDOR) return { createdByUserId: user.id };
    if (user.role === Role.TECNICO) {
      return techViewAll ? {} : { assignments: { some: { userId: user.id } } };
    }
    return { id: '__none__' };
  }

  private assertCanView(
    user: AuthUser,
    sellerId: string,
    assignedIds: string[],
    techViewAll: boolean = false,
  ) {
    if (user.role === Role.ADMIN || user.role === Role.ASISTENTE) return;
    if (user.role === Role.VENDEDOR && user.id === sellerId) return;
    if (user.role === Role.TECNICO) {
      if (techViewAll) return;
      if (assignedIds.includes(user.id)) return;
    }
    throw new ForbiddenException('No autorizado para ver este servicio');
  }

  private assertCanOperate(user: AuthUser, sellerId: string, assignedIds: string[]) {
    if (user.role === Role.ADMIN || user.role === Role.ASISTENTE) return;
    if (user.role === Role.TECNICO && assignedIds.includes(user.id)) return;
    if (user.role === Role.VENDEDOR && user.id === sellerId) return;
    throw new ForbiddenException('No autorizado para modificar este servicio');
  }

  private assertCanCritical(user: AuthUser, sellerId: string) {
    if (user.role === Role.ADMIN || user.role === Role.ASISTENTE) return;
    if (user.role === Role.VENDEDOR && user.id === sellerId) return;
    throw new ForbiddenException('No autorizado para esta acción');
  }

  private canForce(user: AuthUser) {
    return user.role === Role.ADMIN || user.role === Role.ASISTENTE;
  }

  private isValidTransition(current: ServiceStatus, next: ServiceStatus): boolean {
    if (current === next) return true;
    const map: Record<ServiceStatus, ServiceStatus[]> = {
      [ServiceStatus.RESERVED]: [ServiceStatus.SURVEY, ServiceStatus.CANCELLED],
      [ServiceStatus.SURVEY]: [ServiceStatus.SCHEDULED, ServiceStatus.CANCELLED],
      [ServiceStatus.SCHEDULED]: [ServiceStatus.IN_PROGRESS, ServiceStatus.CANCELLED],
      [ServiceStatus.IN_PROGRESS]: [ServiceStatus.COMPLETED, ServiceStatus.WARRANTY, ServiceStatus.CANCELLED],
      [ServiceStatus.COMPLETED]: [ServiceStatus.WARRANTY, ServiceStatus.CLOSED],
      [ServiceStatus.WARRANTY]: [ServiceStatus.IN_PROGRESS, ServiceStatus.CLOSED],
      [ServiceStatus.CLOSED]: [],
      [ServiceStatus.CANCELLED]: [],
    };
    return map[current].includes(next);
  }

  private parseType(value: string): ServiceType {
    const key = value.trim().toLowerCase();
    const map: Record<string, ServiceType> = {
      installation: ServiceType.INSTALLATION,
      maintenance: ServiceType.MAINTENANCE,
      warranty: ServiceType.WARRANTY,
      pos_support: ServiceType.POS_SUPPORT,
      other: ServiceType.OTHER,
    };
    const parsed = map[key];
    if (!parsed) throw new BadRequestException('Tipo de servicio inválido');
    return parsed;
  }

  private parseStatus(value: string): ServiceStatus {
    const key = value.trim().toLowerCase();
    const map: Record<string, ServiceStatus> = {
      reserved: ServiceStatus.RESERVED,
      survey: ServiceStatus.SURVEY,
      scheduled: ServiceStatus.SCHEDULED,
      in_progress: ServiceStatus.IN_PROGRESS,
      completed: ServiceStatus.COMPLETED,
      warranty: ServiceStatus.WARRANTY,
      closed: ServiceStatus.CLOSED,
      cancelled: ServiceStatus.CANCELLED,
    };
    const parsed = map[key];
    if (!parsed) throw new BadRequestException('Estado inválido');
    return parsed;
  }

  private parseOrderType(value: string): OrderType {
    const key = value.trim().toLowerCase();
    const map: Record<string, OrderType> = {
      reserva: OrderType.RESERVA,
      servicio: OrderType.MANTENIMIENTO, // legacy
      levantamiento: OrderType.LEVANTAMIENTO,
      garantia: OrderType.GARANTIA,
      mantenimiento: OrderType.MANTENIMIENTO,
      instalacion: OrderType.INSTALACION,
    };
    const parsed = map[key];
    if (!parsed) throw new BadRequestException('Tipo de orden inválido');
    return parsed;
  }

  private parsePhase(value: string): ServicePhaseType {
    const key = value.trim().toLowerCase();
    const map: Record<string, ServicePhaseType> = {
      reserva: ServicePhaseType.RESERVA,
      levantamiento: ServicePhaseType.LEVANTAMIENTO,
      instalacion: ServicePhaseType.INSTALACION,
      mantenimiento: ServicePhaseType.MANTENIMIENTO,
      garantia: ServicePhaseType.GARANTIA,
    };
    const parsed = map[key];
    if (!parsed) throw new BadRequestException('Fase inválida');
    return parsed;
  }

  private orderTypeWhere(value: string): Prisma.ServiceWhereInput {
    const key = value.trim().toLowerCase();

    if (key === 'mantenimiento' || key === 'servicio') {
      return { orderType: { in: [OrderType.MANTENIMIENTO, OrderType.SERVICIO] } };
    }

    return { orderType: this.parseOrderType(key) };
  }

  private parseOrderState(value: string): OrderState {
    const key = value.trim().toLowerCase();
    const map: Record<string, OrderState> = {
      pending: OrderState.PENDING,
      confirmed: OrderState.CONFIRMED,
      assigned: OrderState.ASSIGNED,
      in_progress: OrderState.IN_PROGRESS,
      finalized: OrderState.FINALIZED,
      cancelled: OrderState.CANCELLED,
      rescheduled: OrderState.RESCHEDULED,
    };
    const parsed = map[key];
    if (!parsed) throw new BadRequestException('Estado de orden inválido');
    return parsed;
  }

  private parseAdminPhase(value: string): AdminOrderPhase {
    const key = value.trim().toLowerCase();
    const map: Record<string, AdminOrderPhase> = {
      reserva: AdminOrderPhase.RESERVA,
      confirmacion: AdminOrderPhase.CONFIRMACION,
      programacion: AdminOrderPhase.PROGRAMACION,
      ejecucion: AdminOrderPhase.EJECUCION,
      revision: AdminOrderPhase.REVISION,
      facturacion: AdminOrderPhase.FACTURACION,
      cierre: AdminOrderPhase.CIERRE,
      cancelada: AdminOrderPhase.CANCELADA,
    };
    const parsed = map[key];
    if (!parsed) throw new BadRequestException('Fase administrativa inválida');
    return parsed;
  }

  private parseAdminStatus(value: string): AdminOrderStatus {
    const key = value.trim().toLowerCase();
    const map: Record<string, AdminOrderStatus> = {
      pendiente: AdminOrderStatus.PENDIENTE,
      confirmada: AdminOrderStatus.CONFIRMADA,
      asignada: AdminOrderStatus.ASIGNADA,
      en_camino: AdminOrderStatus.EN_CAMINO,
      en_proceso: AdminOrderStatus.EN_PROCESO,
      finalizada: AdminOrderStatus.FINALIZADA,
      reagendada: AdminOrderStatus.REAGENDADA,
      cancelada: AdminOrderStatus.CANCELADA,
      cerrada: AdminOrderStatus.CERRADA,
    };
    const parsed = map[key];
    if (!parsed) throw new BadRequestException('Estado administrativo inválido');
    return parsed;
  }

  private parseAssignRole(value: string): ServiceAssignmentRole {
    return value === 'lead' ? ServiceAssignmentRole.LEAD : ServiceAssignmentRole.ASSISTANT;
  }

  private parseUpdateType(value: string): ServiceUpdateType {
    const map: Record<string, ServiceUpdateType> = {
      status_change: ServiceUpdateType.STATUS_CHANGE,
      note: ServiceUpdateType.NOTE,
      schedule_change: ServiceUpdateType.SCHEDULE_CHANGE,
      assignment_change: ServiceUpdateType.ASSIGNMENT_CHANGE,
      payment_update: ServiceUpdateType.PAYMENT_UPDATE,
      step_update: ServiceUpdateType.STEP_UPDATE,
    };
    const parsed = map[value];
    if (!parsed) throw new BadRequestException('Tipo de actualización inválido');
    return parsed;
  }

  private toApiType(value: ServiceType): string {
    const map: Record<ServiceType, string> = {
      [ServiceType.INSTALLATION]: 'installation',
      [ServiceType.MAINTENANCE]: 'maintenance',
      [ServiceType.WARRANTY]: 'warranty',
      [ServiceType.POS_SUPPORT]: 'pos_support',
      [ServiceType.OTHER]: 'other',
    };
    return map[value];
  }

  private toApiStatus(value: ServiceStatus): string {
    const map: Record<ServiceStatus, string> = {
      [ServiceStatus.RESERVED]: 'reserved',
      [ServiceStatus.SURVEY]: 'survey',
      [ServiceStatus.SCHEDULED]: 'scheduled',
      [ServiceStatus.IN_PROGRESS]: 'in_progress',
      [ServiceStatus.COMPLETED]: 'completed',
      [ServiceStatus.WARRANTY]: 'warranty',
      [ServiceStatus.CLOSED]: 'closed',
      [ServiceStatus.CANCELLED]: 'cancelled',
    };
    return map[value];
  }

  private toApiAssignRole(value: ServiceAssignmentRole): string {
    return value === ServiceAssignmentRole.LEAD ? 'lead' : 'assistant';
  }

  private toApiUpdateType(value: ServiceUpdateType): string {
    const map: Record<ServiceUpdateType, string> = {
      [ServiceUpdateType.STATUS_CHANGE]: 'status_change',
      [ServiceUpdateType.NOTE]: 'note',
      [ServiceUpdateType.SCHEDULE_CHANGE]: 'schedule_change',
      [ServiceUpdateType.ASSIGNMENT_CHANGE]: 'assignment_change',
      [ServiceUpdateType.PAYMENT_UPDATE]: 'payment_update',
      [ServiceUpdateType.STEP_UPDATE]: 'step_update',
      [ServiceUpdateType.FILE_UPLOAD]: 'file_upload',
      [ServiceUpdateType.WARRANTY_CREATED]: 'warranty_created',
    };
    return map[value];
  }

  private toApiOrderType(value: OrderType): string {
    const map: Record<OrderType, string> = {
      [OrderType.RESERVA]: 'reserva',
      [OrderType.SERVICIO]: 'mantenimiento',
      [OrderType.LEVANTAMIENTO]: 'levantamiento',
      [OrderType.GARANTIA]: 'garantia',
      [OrderType.MANTENIMIENTO]: 'mantenimiento',
      [OrderType.INSTALACION]: 'instalacion',
    };
    return map[value];
  }

  private toApiPhase(value: ServicePhaseType): string {
    const map: Record<ServicePhaseType, string> = {
      [ServicePhaseType.RESERVA]: 'reserva',
      [ServicePhaseType.LEVANTAMIENTO]: 'levantamiento',
      [ServicePhaseType.INSTALACION]: 'instalacion',
      [ServicePhaseType.MANTENIMIENTO]: 'mantenimiento',
      [ServicePhaseType.GARANTIA]: 'garantia',
    };
    return map[value];
  }

  private toApiOrderState(value: OrderState): string {
    const map: Record<OrderState, string> = {
      [OrderState.PENDING]: 'pending',
      [OrderState.CONFIRMED]: 'confirmed',
      [OrderState.ASSIGNED]: 'assigned',
      [OrderState.IN_PROGRESS]: 'in_progress',
      [OrderState.FINALIZED]: 'finalized',
      [OrderState.CANCELLED]: 'cancelled',
      [OrderState.RESCHEDULED]: 'rescheduled',
    };
    return map[value];
  }

  private toApiAdminPhase(value: AdminOrderPhase): string {
    const map: Record<AdminOrderPhase, string> = {
      [AdminOrderPhase.RESERVA]: 'reserva',
      [AdminOrderPhase.CONFIRMACION]: 'confirmacion',
      [AdminOrderPhase.PROGRAMACION]: 'programacion',
      [AdminOrderPhase.EJECUCION]: 'ejecucion',
      [AdminOrderPhase.REVISION]: 'revision',
      [AdminOrderPhase.FACTURACION]: 'facturacion',
      [AdminOrderPhase.CIERRE]: 'cierre',
      [AdminOrderPhase.CANCELADA]: 'cancelada',
    };
    return map[value];
  }

  private toApiAdminStatus(value: AdminOrderStatus): string {
    const map: Record<AdminOrderStatus, string> = {
      [AdminOrderStatus.PENDIENTE]: 'pendiente',
      [AdminOrderStatus.CONFIRMADA]: 'confirmada',
      [AdminOrderStatus.ASIGNADA]: 'asignada',
      [AdminOrderStatus.EN_CAMINO]: 'en_camino',
      [AdminOrderStatus.EN_PROCESO]: 'en_proceso',
      [AdminOrderStatus.FINALIZADA]: 'finalizada',
      [AdminOrderStatus.REAGENDADA]: 'reagendada',
      [AdminOrderStatus.CANCELADA]: 'cancelada',
      [AdminOrderStatus.CERRADA]: 'cerrada',
    };
    return map[value];
  }

  private scheduleRangeWhere(from?: string, to?: string): Prisma.ServiceWhereInput {
    const scheduledStart: Prisma.DateTimeFilter = {};

    if (from) {
      const fromDate = new Date(from);
      if (Number.isNaN(fromDate.getTime())) throw new BadRequestException('from inválido');
      scheduledStart.gte = fromDate;
    }

    if (to) {
      const toDate = new Date(to);
      if (Number.isNaN(toDate.getTime())) throw new BadRequestException('to inválido');
      scheduledStart.lt = new Date(toDate.getTime() + 24 * 60 * 60 * 1000);
    }

    return Object.keys(scheduledStart).length ? { scheduledStart } : {};
  }

  private startOfDay() {
    const now = new Date();
    return new Date(now.getFullYear(), now.getMonth(), now.getDate());
  }

  private endOfDay() {
    const start = this.startOfDay();
    return new Date(start.getTime() + 24 * 60 * 60 * 1000);
  }
}
