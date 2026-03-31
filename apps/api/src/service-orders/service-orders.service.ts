import { randomUUID } from 'node:crypto';
import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import {
  Prisma,
  Role,
  ServiceOrderStatus as PrismaServiceOrderStatus,
  ServiceOrderType as PrismaServiceOrderType,
  type Client,
} from '@prisma/client';
import { RedisService } from '../common/redis/redis.service';
import { PayrollService } from '../payroll/payroll.service';
import { PrismaService } from '../prisma/prisma.service';
import { CatalogRealtimeRelayService } from '../products/catalog-realtime-relay.service';
import { ServiceOrderNotificationsListener } from '../notifications/service-order-notifications.listener';
import { CloneServiceOrderDto } from './dto/clone-service-order.dto';
import { CreateEvidenceDto } from './dto/create-evidence.dto';
import { CreateReportDto } from './dto/create-report.dto';
import { CreateServiceOrderDto } from './dto/create-service-order.dto';
import { UpdateServiceOrderDto } from './dto/update-service-order.dto';
import { UpdateStatusDto } from './dto/update-status.dto';
import {
  ApiServiceEvidenceType,
  ApiServiceOrderCategory,
  ApiServiceOrderStatus,
  ApiServiceOrderType,
  ApiServiceReportType,
  SERVICE_EVIDENCE_TYPE_FROM_DB,
  SERVICE_EVIDENCE_TYPE_TO_DB,
  SERVICE_ORDER_ALLOWED_STATUS_TRANSITIONS,
  SERVICE_ORDER_CATEGORY_FROM_DB,
  SERVICE_ORDER_CATEGORY_TO_DB,
  SERVICE_REPORT_TYPE_FROM_DB,
  SERVICE_REPORT_TYPE_TO_DB,
  SERVICE_ORDER_STATUS_FROM_DB,
  SERVICE_ORDER_STATUS_TO_DB,
  SERVICE_ORDER_TYPE_FROM_DB,
  SERVICE_ORDER_TYPE_TO_DB,
} from './service-orders.constants';

type AuthUser = { id: string; role: Role };

type ServiceOrderWithRelations = Prisma.ServiceOrderGetPayload<{
  include: {
    client: true;
    evidences: { orderBy: { createdAt: 'asc' } };
    reports: { orderBy: { createdAt: 'asc' } };
  };
}>;

type ServiceOrderWithClient = Prisma.ServiceOrderGetPayload<{
  include: {
    client: true;
  };
}>;

type ServiceOrderRecord = Prisma.ServiceOrderGetPayload<object>;

type ServiceSalesOrderWithRelations = Prisma.ServiceOrderGetPayload<{
  include: {
    client: true;
    assignedTo: {
      select: {
        id: true;
        nombreCompleto: true;
        email: true;
      };
    };
    quotation: {
      include: {
        items: {
          orderBy: {
            createdAt: 'asc';
          };
        };
      };
    };
  };
}>;

@Injectable()
export class ServiceOrdersService {
  private readonly logger = new Logger(ServiceOrdersService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly realtime: CatalogRealtimeRelayService,
    private readonly payroll: PayrollService,
    private readonly orderNotifications: ServiceOrderNotificationsListener,
  ) {}

  async create(user: AuthUser, dto: CreateServiceOrderDto) {
    const payload = await this.buildCreatePayload(user, dto);

    try {
      const created = await this.prisma.serviceOrder.create({
        data: payload,
        include: { client: true },
      });
      const mapped = this.mapOrder(created);
      await this.invalidateCachesForOrder(created.id);
      this.emitOrderEvent('service.created', created.id, mapped);
      await this.runNotificationHook(`service.created:${created.id}`, () =>
        this.orderNotifications.handleOrderCreated(created.id),
      );
      return mapped;
    } catch (error) {
      this.rethrowWriteError(error);
    }
  }

  async list(user: AuthUser) {
    const cacheKey = this.buildListCacheKey(user);
    const cached = await this.redis.get<{ items: unknown[] }>(cacheKey);
    if (Array.isArray(cached?.items)) {
      return cached;
    }

    const items = await this.prisma.serviceOrder.findMany({
      include: { client: true },
      orderBy: [{ createdAt: 'desc' }],
    });
    const response = { items: items.map((item) => this.mapOrder(item)) };
    await this.redis.set(cacheKey, response, 30);
    return response;
  }

  async findOne(user: AuthUser, id: string) {
    const cacheKey = this.buildDetailCacheKey(user, id);
    const cached = await this.redis.get<Record<string, unknown>>(cacheKey);
    if (cached) {
      return cached;
    }

    const item = await this.findOrderWithRelationsOrThrow(user, id);
    const response = this.mapOrder(item);
    await this.redis.set(cacheKey, response, 30);
    return response;
  }

  async salesSummary(user: AuthUser, from?: string, to?: string) {
    const where: Prisma.ServiceOrderWhereInput = {
      createdById: user.id,
      status: PrismaServiceOrderStatus.FINALIZADO,
      serviceType: {
        in: [
          PrismaServiceOrderType.INSTALACION,
          PrismaServiceOrderType.MANTENIMIENTO,
        ],
      },
      ...this.buildFinalizedAtRange(from, to),
    };

    const orders = await this.prisma.serviceOrder.findMany({
      where,
      orderBy: { finalizedAt: 'desc' },
      include: {
        client: true,
        assignedTo: {
          select: {
            id: true,
            nombreCompleto: true,
            email: true,
          },
        },
        quotation: {
          include: {
            items: {
              orderBy: { createdAt: 'asc' },
            },
          },
        },
      },
    });

    const items: Array<Record<string, unknown>> = [];
    const skipped: Array<Record<string, unknown>> = [];
    const totals = {
      totalOrders: orders.length,
      eligibleOrders: 0,
      skippedOrders: 0,
      totalQuoted: 0,
      totalCost: 0,
      totalProfit: 0,
      totalOperationalExpense: 0,
      totalProfitAfterExpense: 0,
      totalSellerCommission: 0,
      totalTechnicianCommission: 0,
    };

    for (const order of orders) {
      const evaluated = this.evaluateServiceSalesOrder(order);
      if ('reason' in evaluated) {
        skipped.push(evaluated);
        continue;
      }

      items.push(evaluated);
      totals.eligibleOrders += 1;
      totals.totalQuoted += this.toNumber(evaluated.totalQuoted);
      totals.totalCost += this.toNumber(evaluated.totalCost);
      totals.totalProfit += this.toNumber(evaluated.totalProfit);
      totals.totalOperationalExpense += this.toNumber(evaluated.operationalExpenseAmount);
      totals.totalProfitAfterExpense += this.toNumber(evaluated.profitAfterExpense);
      totals.totalSellerCommission += this.toNumber(evaluated.sellerCommissionAmount);
      totals.totalTechnicianCommission += this.toNumber(evaluated.technicianCommissionAmount);
    }

    totals.skippedOrders = skipped.length;

    return {
      from: from?.trim() || null,
      to: to?.trim() || null,
      items,
      skipped,
      ...totals,
    };
  }

  async update(user: AuthUser, id: string, dto: UpdateServiceOrderDto) {
    const current = await this.findOrderOrThrow(user, id);
    if (user.role === Role.TECNICO) {
      return this.updateAsTechnician(user, current, dto);
    }

    this.assertCanFullyEditOrder(user, current);

    const clientId = this.cleanOptionalText(dto.clientId, dto.client_id) ?? current.clientId;
    const quotationId = this.cleanOptionalText(dto.quotationId, dto.quotation_id) ?? current.quotationId;
    const category = this.cleanOptionalText(dto.category) as ApiServiceOrderCategory | null;
    const serviceType = this.cleanOptionalText(dto.serviceType, dto.service_type) as ApiServiceOrderType | null;
    const technicalNote = this.cleanOptionalText(dto.technicalNote, dto.technical_note);
    const extraRequirements = this.cleanOptionalText(dto.extraRequirements, dto.extra_requirements);
    const scheduledFor = this.hasScheduledForInput(dto)
      ? this.parseOptionalDate(dto.scheduledFor, dto.scheduled_for, 'scheduled_for')
      : current.scheduledFor;
    const assignedToId = this.hasAssignedToInput(dto)
      ? await this.resolveAssignedToId(dto.assignedToId, dto.assigned_to)
      : current.assignedToId;

    await this.assertClientExists(clientId);
    await this.assertQuotationMatchesClient(quotationId, clientId);

    try {
      const updated = await this.prisma.serviceOrder.update({
        where: { id },
        include: { client: true },
        data: {
          clientId,
          quotationId,
          category: category
            ? SERVICE_ORDER_CATEGORY_TO_DB[category]
            : current.category,
          serviceType: serviceType
            ? SERVICE_ORDER_TYPE_TO_DB[serviceType]
            : current.serviceType,
          scheduledFor,
          technicalNote: this.hasTextInput(dto, 'technicalNote', 'technical_note')
            ? technicalNote
            : current.technicalNote,
          extraRequirements: this.hasTextInput(dto, 'extraRequirements', 'extra_requirements')
            ? extraRequirements
            : current.extraRequirements,
          assignedToId,
        },
      });
      const mapped = this.mapOrder(updated);
      await this.invalidateCachesForOrder(updated.id);
      this.emitOrderEvent('service.updated', updated.id, mapped);
      await this.runNotificationHook(`service.updated:${updated.id}`, () =>
        this.orderNotifications.handleOrderUpdated(updated.id),
      );
      return mapped;
    } catch (error) {
      this.rethrowWriteError(error);
    }
  }

  async updateStatus(user: AuthUser, id: string, dto: UpdateStatusDto) {
    const item = await this.findOrderOrThrow(user, id);
    this.assertCanModifyOrder(user, item);

    const previousStatus = this.toApiStatus(item.status);
    const nextStatus = dto.status as ApiServiceOrderStatus;
    this.assertValidStatusTransition(previousStatus, nextStatus);
    const resolvedAssignedToId =
      nextStatus === 'finalizado' && user.role === Role.TECNICO
        ? user.id
        : item.assignedToId;

    try {
      const updated = await this.prisma.serviceOrder.update({
        where: { id },
        include: { client: true },
        data: {
          status: SERVICE_ORDER_STATUS_TO_DB[nextStatus],
          assignedToId: resolvedAssignedToId,
          finalizedAt: nextStatus === 'finalizado' ? new Date() : item.finalizedAt,
        },
      });
      if (nextStatus === 'finalizado') {
        await this.queueTechnicalCommissionForPayroll(updated.id, user.id);
      }
      const mapped = this.mapOrder(updated);
      await this.invalidateCachesForOrder(updated.id);
      this.emitOrderEvent('service.status_changed', updated.id, mapped);
      await this.runNotificationHook(`service.status_changed:${updated.id}:${previousStatus}->${nextStatus}`, () =>
        this.orderNotifications.handleStatusChanged(updated.id, previousStatus, nextStatus),
      );
      return mapped;
    } catch (error) {
      this.rethrowWriteError(error);
    }
  }

  async confirm(user: AuthUser, id: string) {
    const item = await this.findOrderOrThrow(user, id);

    if (user.role !== Role.TECNICO) {
      throw new ForbiddenException('Solo un técnico puede confirmar esta orden');
    }

    if (item.status !== PrismaServiceOrderStatus.PENDIENTE) {
      throw new BadRequestException('Solo se pueden confirmar órdenes pendientes');
    }

    if (item.technicianConfirmedById === user.id) {
      const snapshot = await this.findOrderWithRelationsOrThrow(user, id);
      return this.mapOrder(snapshot);
    }

    if (item.technicianConfirmedById && item.technicianConfirmedById !== user.id) {
      throw new BadRequestException('La orden ya fue confirmada por otro técnico');
    }

    if (item.assignedToId && item.assignedToId !== user.id) {
      throw new ForbiddenException('La orden está asignada a otro técnico');
    }

    try {
      const updated = await this.prisma.serviceOrder.update({
        where: { id },
        include: { client: true },
        data: {
          assignedToId: item.assignedToId ?? user.id,
          technicianConfirmedAt: item.technicianConfirmedAt ?? new Date(),
          technicianConfirmedById: item.technicianConfirmedById ?? user.id,
        },
      });
      const mapped = this.mapOrder(updated);
      await this.invalidateCachesForOrder(updated.id);
      this.emitOrderEvent('service.confirmed', updated.id, mapped);
      await this.runNotificationHook(`service.confirmed:${updated.id}:${user.id}`, () =>
        this.orderNotifications.handleOrderConfirmed(updated.id, user.id),
      );
      return mapped;
    } catch (error) {
      this.rethrowWriteError(error);
    }
  }

  async addEvidence(user: AuthUser, id: string, dto: CreateEvidenceDto) {
    const item = await this.findOrderOrThrow(user, id);
    this.assertCanModifyOrder(user, item);
    this.assertCanAddEvidenceType(user, dto.type as ApiServiceEvidenceType);

    const content = this.cleanRequiredText(dto.content, 'content');

    try {
      const created = await this.prisma.serviceEvidence.create({
        data: {
          serviceOrderId: item.id,
          type: SERVICE_EVIDENCE_TYPE_TO_DB[dto.type as ApiServiceEvidenceType],
          content,
          createdById: user.id,
        },
      });
      await this.invalidateCachesForOrder(item.id);
      const snapshot = await this.findOrderWithRelationsOrThrow(user, item.id);
      this.emitOrderEvent('service.updated', item.id, this.mapOrder(snapshot));
      return this.mapEvidence(created);
    } catch (error) {
      this.rethrowWriteError(error);
    }
  }

  async addReport(user: AuthUser, id: string, dto: CreateReportDto) {
    const item = await this.findOrderOrThrow(user, id);
    this.assertCanModifyOrder(user, item);
    this.assertTechnicalOutputAccess(user);

    const type = dto.type as ApiServiceReportType;
    const report = this.cleanRequiredText(dto.report, 'report');

    try {
      const created = await this.prisma.serviceReport.create({
        data: {
          serviceOrderId: item.id,
          type: SERVICE_REPORT_TYPE_TO_DB[type],
          report,
          createdById: user.id,
        },
      });
      await this.invalidateCachesForOrder(item.id);
      const snapshot = await this.findOrderWithRelationsOrThrow(user, item.id);
      this.emitOrderEvent('service.updated', item.id, this.mapOrder(snapshot));
      return this.mapReport(created);
    } catch (error) {
      this.rethrowWriteError(error);
    }
  }

  async clone(user: AuthUser, id: string, dto: CloneServiceOrderDto) {
    const original = await this.findOrderOrThrow(user, id);

    const serviceType = this.requireAliasValue(dto.serviceType, dto.service_type, 'service_type');
    const assignedToId = await this.resolveAssignedToId(dto.assignedToId, dto.assigned_to);
    const technicalNote = this.cleanOptionalText(dto.technicalNote, dto.technical_note) ?? original.technicalNote;
    const extraRequirements =
      this.cleanOptionalText(dto.extraRequirements, dto.extra_requirements) ?? original.extraRequirements;

    try {
      const cloned = await this.prisma.serviceOrder.create({
        include: { client: true },
        data: {
          clientId: original.clientId,
          quotationId: original.quotationId,
          category: original.category,
          serviceType: SERVICE_ORDER_TYPE_TO_DB[serviceType as ApiServiceOrderType],
          status: SERVICE_ORDER_STATUS_TO_DB.pendiente,
          technicalNote,
          extraRequirements,
          parentOrderId: original.id,
          createdById: user.id,
          assignedToId,
        },
      });
      const mapped = this.mapOrder(cloned);
      await this.invalidateCachesForOrder(cloned.id);
      this.emitOrderEvent('service.created', cloned.id, mapped);
      await this.runNotificationHook(`service.created:${cloned.id}`, () =>
        this.orderNotifications.handleOrderCreated(cloned.id),
      );
      return mapped;
    } catch (error) {
      this.rethrowWriteError(error);
    }
  }

  async remove(user: AuthUser, id: string) {
    this.assertAdminDelete(user);
    await this.findOrderOrThrow(user, id);

    try {
      await this.prisma.serviceOrder.delete({ where: { id } });
      await this.invalidateCachesForOrder(id);
      this.emitOrderEvent('service.deleted', id);
      return { ok: true };
    } catch (error) {
      this.rethrowWriteError(error);
    }
  }

  async purgeAllForDebug(user: AuthUser) {
    this.assertAdminDelete(user);

    const deleted = await this.prisma.serviceOrder.deleteMany();
    await this.redis.delByPattern('service-orders:list:*');
    await this.redis.delByPattern('service-orders:detail:*');

    return {
      ok: true,
      deletedServiceOrders: deleted.count,
    };
  }

  private async updateAsTechnician(
    user: AuthUser,
    current: ServiceOrderRecord,
    dto: UpdateServiceOrderDto,
  ) {
    this.assertCanModifyOrder(user, current);
    this.assertTecnicoUpdateDoesNotChangeProtectedFields(current, dto);

    const data = this.buildTecnicoUpdateData(dto, current);
    if (!data) {
      return this.mapOrder(current);
    }

    try {
      const updated = await this.prisma.serviceOrder.update({
        where: { id: current.id },
        include: { client: true },
        data,
      });
      const mapped = this.mapOrder(updated);
      await this.invalidateCachesForOrder(updated.id);
      this.emitOrderEvent('service.updated', updated.id, mapped);
      return mapped;
    } catch (error) {
      this.rethrowWriteError(error);
    }
  }

  private buildListCacheKey(user: AuthUser) {
    return `service-orders:list:${user.role}:${user.id}`;
  }

  private buildDetailCacheKey(user: AuthUser, id: string) {
    return `service-orders:detail:${user.role}:${user.id}:${id}`;
  }

  private async invalidateCachesForOrder(id: string) {
    await this.redis.delByPattern('service-orders:list:*');
    await this.redis.delByPattern(`service-orders:detail:*:*:${id}`);
  }

  private emitOrderEvent(type: string, serviceId: string, service?: unknown) {
    this.realtime.emitOps('service.event', {
      eventId: randomUUID(),
      type,
      serviceId,
      ...(service == null ? {} : { service }),
      occurredAt: new Date().toISOString(),
    });
  }

  private async buildCreatePayload(
    user: AuthUser,
    dto: CreateServiceOrderDto,
  ): Promise<Prisma.ServiceOrderUncheckedCreateInput> {
    const clientId = this.requireAliasValue(dto.clientId, dto.client_id, 'client_id');
    const quotationId = this.requireAliasValue(dto.quotationId, dto.quotation_id, 'quotation_id');
    const category = this.requireDirectValue(dto.category, 'category') as ApiServiceOrderCategory;
    const serviceType = this.requireAliasValue(dto.serviceType, dto.service_type, 'service_type') as ApiServiceOrderType;
    const scheduledFor = this.parseOptionalDate(dto.scheduledFor, dto.scheduled_for, 'scheduled_for');
    const technicalNote = this.cleanOptionalText(dto.technicalNote, dto.technical_note);
    const extraRequirements = this.cleanOptionalText(dto.extraRequirements, dto.extra_requirements);
    const assignedToId = await this.resolveAssignedToId(dto.assignedToId, dto.assigned_to);

    await this.assertClientExists(clientId);
    await this.assertQuotationMatchesClient(quotationId, clientId);

    return {
      clientId,
      quotationId,
      category: SERVICE_ORDER_CATEGORY_TO_DB[category],
      serviceType: SERVICE_ORDER_TYPE_TO_DB[serviceType],
      status: SERVICE_ORDER_STATUS_TO_DB.pendiente,
      scheduledFor,
      technicalNote,
      extraRequirements,
      createdById: user.id,
      assignedToId,
    };
  }

  private evaluateServiceSalesOrder(order: ServiceSalesOrderWithRelations) {
    const quotation = order.quotation;
    const quotationItems = quotation.items ?? [];
    if (!quotationItems.length) {
      return this.buildSkippedServiceSalesOrder(order, 'La cotización no tiene líneas registradas');
    }

    let missingCostItemsCount = 0;

    for (const item of quotationItems) {
      if (item.costUnitSnapshot == null || item.subtotalCost == null || item.profit == null) {
        missingCostItemsCount += 1;
      }
    }

    if (missingCostItemsCount > 0) {
      return this.buildSkippedServiceSalesOrder(
        order,
        missingCostItemsCount === quotationItems.length
          ? 'La cotización depende de artículos sin costo trazable desde catálogo'
          : 'La cotización contiene líneas sin costo trazable desde catálogo',
        missingCostItemsCount,
      );
    }

    if (quotation.totalCost == null || quotation.totalProfit == null) {
      return this.buildSkippedServiceSalesOrder(
        order,
        'La cotización no tiene utilidad histórica persistida',
        missingCostItemsCount,
      );
    }

    const totalQuoted = this.toNumber(quotation.total);
    const totalCost = this.toNumber(quotation.totalCost);
    const totalProfit = this.toNumber(quotation.totalProfit);
    const operationalExpenseRate =
      order.serviceType === PrismaServiceOrderType.INSTALACION ? 0.3 : 0.1;
    const operationalExpenseAmount = totalProfit > 0 ? totalProfit * operationalExpenseRate : 0;
    const profitAfterExpense = Math.max(0, totalProfit - operationalExpenseAmount);
    const sellerCommissionAmount = profitAfterExpense > 0 ? profitAfterExpense * 0.1 : 0;
    const technicianCommissionAmount = profitAfterExpense > 0 ? profitAfterExpense * 0.1 : 0;

    return {
      orderId: order.id,
      quotationId: order.quotationId,
      customerId: order.clientId,
      customerName: order.client.nombre,
      category: SERVICE_ORDER_CATEGORY_FROM_DB[order.category],
      serviceType: SERVICE_ORDER_TYPE_FROM_DB[order.serviceType],
      status: SERVICE_ORDER_STATUS_FROM_DB[order.status],
      finalizedAt: order.finalizedAt,
      createdById: order.createdById,
      technicianId: order.assignedToId,
      technicianName: order.assignedTo?.nombreCompleto ?? null,
      technicianEmail: order.assignedTo?.email ?? null,
      itemsCount: quotationItems.length,
      totalQuoted,
      totalCost,
      totalProfit,
      operationalExpenseRate,
      operationalExpenseAmount,
      profitAfterExpense,
      sellerCommissionRate: 0.1,
      sellerCommissionAmount,
      technicianCommissionRate: 0.1,
      technicianCommissionAmount,
    };
  }

  private buildSkippedServiceSalesOrder(
    order: ServiceSalesOrderWithRelations,
    reason: string,
    missingCostItemsCount = 0,
  ) {
    return {
      orderId: order.id,
      quotationId: order.quotationId,
      customerId: order.clientId,
      customerName: order.client.nombre,
      category: SERVICE_ORDER_CATEGORY_FROM_DB[order.category],
      serviceType: SERVICE_ORDER_TYPE_FROM_DB[order.serviceType],
      status: SERVICE_ORDER_STATUS_FROM_DB[order.status],
      finalizedAt: order.finalizedAt,
      createdById: order.createdById,
      technicianId: order.assignedToId,
      technicianName: order.assignedTo?.nombreCompleto ?? null,
      reason,
      itemsCount: order.quotation.items.length,
      missingCostItemsCount,
      totalQuoted: this.toNumber(order.quotation.total),
    };
  }

  private async queueTechnicalCommissionForPayroll(
    serviceOrderId: string,
    finalizedByUserId?: string,
  ) {
    const order = await this.prisma.serviceOrder.findUnique({
      where: { id: serviceOrderId },
      include: {
        client: true,
        assignedTo: {
          select: {
            id: true,
            nombreCompleto: true,
            email: true,
          },
        },
        quotation: {
          include: {
            items: {
              orderBy: { createdAt: 'asc' },
            },
          },
        },
      },
    });

    if (!order) {
      return;
    }

    if (order.serviceType !== PrismaServiceOrderType.INSTALACION) {
      return;
    }

    if (!order.assignedToId || !order.finalizedAt) {
      return;
    }

    const evaluated = this.evaluateServiceSalesOrder(order);
    if ('reason' in evaluated) {
      return;
    }

    const ownerId = await this.payroll.resolveCompanyOwnerId(order.createdById);
    const concept = [
      'Comisión técnica por instalación',
      order.client.nombre.trim(),
      `OS ${order.id.slice(0, 8).toUpperCase()}`,
    ].join(' · ');

    await this.payroll.queueTechnicalServiceCommissionRequest({
      ownerId,
      serviceOrderId: order.id,
      quotationId: order.quotationId,
      technicianUserId: order.assignedToId,
      createdByUserId: finalizedByUserId ?? order.createdById,
      serviceType: order.serviceType,
      finalizedAt: order.finalizedAt,
      profitAfterExpense: this.toNumber(evaluated.profitAfterExpense),
      commissionRate: this.toNumber(evaluated.technicianCommissionRate),
      commissionAmount: this.toNumber(evaluated.technicianCommissionAmount),
      concept,
    });
  }

  private async findOrderOrThrow(
    user: AuthUser,
    id: string,
  ): Promise<ServiceOrderRecord> {
    const item = await this.prisma.serviceOrder.findUnique({
      where: { id },
    });

    if (!item) {
      throw new NotFoundException('Orden de servicio no encontrada');
    }

    return item;
  }

  private async findOrderWithRelationsOrThrow(
    user: AuthUser,
    id: string,
  ): Promise<ServiceOrderWithRelations> {
    const item = await this.prisma.serviceOrder.findUnique({
      where: { id },
      include: {
        client: true,
        evidences: { orderBy: { createdAt: 'asc' } },
        reports: { orderBy: { createdAt: 'asc' } },
      },
    });

    if (!item) {
      throw new NotFoundException('Orden de servicio no encontrada');
    }

    return item;
  }

  private assertCanOperate(
    user: AuthUser,
    item: {
      createdById: string;
      assignedToId: string | null;
    },
  ) {
    if (user.role === Role.ADMIN || user.role === Role.ASISTENTE) return;
    if (user.role === Role.VENDEDOR && item.createdById === user.id) return;
    if (user.role === Role.TECNICO) return;
    throw new ForbiddenException('No puedes operar esta orden de servicio');
  }

  private assertAdmin(user: AuthUser) {
    if (user.role !== Role.ADMIN) {
      throw new ForbiddenException('Solo administradores pueden modificar o eliminar órdenes');
    }
  }

  private hasAssignedToInput(dto: UpdateServiceOrderDto) {
    return Object.prototype.hasOwnProperty.call(dto, 'assignedToId') ||
      Object.prototype.hasOwnProperty.call(dto, 'assigned_to');
  }

  private hasScheduledForInput(dto: UpdateServiceOrderDto) {
    return Object.prototype.hasOwnProperty.call(dto, 'scheduledFor') ||
      Object.prototype.hasOwnProperty.call(dto, 'scheduled_for');
  }

  private assertCanFullyEditOrder(
    user: AuthUser,
    item: { createdById: string },
  ) {
    if (user.role === Role.ADMIN || item.createdById === user.id) {
      return;
    }
    throw new ForbiddenException('Not authorized to modify this order');
  }

  private assertAdminEdit(user: AuthUser) {
    if (user.role !== Role.ADMIN) {
      throw new ForbiddenException('Not authorized to modify this order');
    }
  }

  private assertAdminDelete(user: AuthUser) {
    if (user.role !== Role.ADMIN) {
      throw new ForbiddenException('Only admin can delete orders');
    }
  }

  private assertCanModifyOrder(user: AuthUser, item: { createdById: string; assignedToId: string | null }) {
    if (user.role === Role.ADMIN) {
      return;
    }
    if (user.role === Role.TECNICO) {
      return;
    }
    if (item.createdById === user.id) {
      return;
    }
    throw new ForbiddenException('Not authorized to modify this order');
  }

  private assertTechnicalOutputAccess(user: AuthUser) {
    if (user.role === Role.ADMIN || user.role === Role.TECNICO) {
      return;
    }
    throw new ForbiddenException('Not authorized to modify this order');
  }

  private hasTextInput(dto: UpdateServiceOrderDto, ...keys: Array<keyof UpdateServiceOrderDto>) {
    return keys.some((key) => Object.prototype.hasOwnProperty.call(dto, key));
  }

  private buildTecnicoUpdateData(
    dto: UpdateServiceOrderDto,
    current: ServiceOrderRecord,
  ): Prisma.ServiceOrderUncheckedUpdateInput | null {
    const data: Prisma.ServiceOrderUncheckedUpdateInput = {};

    if (this.hasTextInput(dto, 'technicalNote', 'technical_note')) {
      const nextTechnicalNote = this.cleanOptionalText(dto.technicalNote, dto.technical_note);
      if (nextTechnicalNote !== current.technicalNote) {
        data.technicalNote = nextTechnicalNote;
      }
    }

    if (this.hasTextInput(dto, 'extraRequirements', 'extra_requirements')) {
      const nextExtraRequirements = this.cleanOptionalText(dto.extraRequirements, dto.extra_requirements);
      if (nextExtraRequirements !== current.extraRequirements) {
        data.extraRequirements = nextExtraRequirements;
      }
    }

    return Object.keys(data).length > 0 ? data : null;
  }

  private assertTecnicoUpdateDoesNotChangeProtectedFields(
    current: ServiceOrderRecord,
    dto: UpdateServiceOrderDto,
  ) {
    const nextClientId = this.cleanOptionalText(dto.clientId, dto.client_id);
    if ((dto.clientId !== undefined || dto.client_id !== undefined) && nextClientId !== current.clientId) {
      throw new ForbiddenException('Not authorized to modify this order');
    }

    const nextQuotationId = this.cleanOptionalText(dto.quotationId, dto.quotation_id);
    if (
      (dto.quotationId !== undefined || dto.quotation_id !== undefined) &&
      nextQuotationId !== current.quotationId
    ) {
      throw new ForbiddenException('Not authorized to modify this order');
    }

    const nextCategory = this.cleanOptionalText(dto.category);
    if (dto.category !== undefined && nextCategory !== SERVICE_ORDER_CATEGORY_FROM_DB[current.category]) {
      throw new ForbiddenException('Not authorized to modify this order');
    }

    const nextServiceType = this.cleanOptionalText(dto.serviceType, dto.service_type);
    if (
      (dto.serviceType !== undefined || dto.service_type !== undefined) &&
      nextServiceType !== SERVICE_ORDER_TYPE_FROM_DB[current.serviceType]
    ) {
      throw new ForbiddenException('Not authorized to modify this order');
    }

    const nextAssignedToId = this.cleanOptionalText(dto.assignedToId, dto.assigned_to);
    if (
      (dto.assignedToId !== undefined || dto.assigned_to !== undefined) &&
      nextAssignedToId !== current.assignedToId
    ) {
      throw new ForbiddenException('Not authorized to modify this order');
    }

    if (dto.scheduledFor !== undefined || dto.scheduled_for !== undefined) {
      const nextScheduledFor = this.parseOptionalDate(dto.scheduledFor, dto.scheduled_for, 'scheduled_for');
      const currentIso = current.scheduledFor?.toISOString() ?? null;
      const nextIso = nextScheduledFor?.toISOString() ?? null;
      if (currentIso !== nextIso) {
        throw new ForbiddenException('Not authorized to modify this order');
      }
    }
  }

  private assertCanAddEvidenceType(user: AuthUser, type: ApiServiceEvidenceType) {
    if (type.startsWith('referencia_')) {
      return;
    }

    this.assertTechnicalOutputAccess(user);
  }

  private assertCanManageTechnicalOutputs(user: AuthUser) {
    if (user.role === Role.ADMIN || user.role === Role.TECNICO) {
      return;
    }

    throw new ForbiddenException('Solo admin y técnico pueden registrar evidencia técnica o reportes');
  }

  private async assertClientExists(clientId: string) {
    const client = await this.prisma.client.findUnique({
      where: { id: clientId },
      select: { id: true },
    });
    if (!client) throw new NotFoundException('Cliente no encontrado');
  }

  private async assertQuotationMatchesClient(quotationId: string, clientId: string) {
    const quotation = await this.prisma.cotizacion.findUnique({
      where: { id: quotationId },
      select: { id: true, customerId: true },
    });
    if (!quotation) throw new NotFoundException('Cotización no encontrada');
    if (quotation.customerId && quotation.customerId !== clientId) {
      throw new BadRequestException('La cotización indicada no pertenece al cliente seleccionado');
    }
  }

  private async resolveAssignedToId(value?: string | null, alias?: string | null) {
    const assignedToId = this.cleanOptionalText(value, alias);
    if (!assignedToId) return null;

    const technician = await this.prisma.user.findUnique({
      where: { id: assignedToId },
      select: { id: true, role: true },
    });

    if (!technician) throw new NotFoundException('Usuario asignado no encontrado');
    if (technician.role !== Role.TECNICO) {
      throw new BadRequestException('assigned_to debe pertenecer a un técnico');
    }

    return technician.id;
  }

  private assertValidStatusTransition(
    current: ApiServiceOrderStatus,
    next: ApiServiceOrderStatus,
  ) {
    if (current === next) {
      throw new BadRequestException('La orden ya tiene ese estado');
    }

    const allowed = SERVICE_ORDER_ALLOWED_STATUS_TRANSITIONS[current];
    if (!allowed.includes(next)) {
      throw new BadRequestException(
        `Transición inválida de estado: ${current} -> ${next}`,
      );
    }
  }

  private requireAliasValue(primary: string | undefined, alias: string | undefined, fieldName: string) {
    const value = this.cleanOptionalText(primary, alias);
    if (!value) {
      throw new BadRequestException(`El campo ${fieldName} es requerido`);
    }
    return value;
  }

  private requireDirectValue(value: string | undefined, fieldName: string) {
    const normalized = this.cleanOptionalText(value);
    if (!normalized) {
      throw new BadRequestException(`El campo ${fieldName} es requerido`);
    }
    return normalized;
  }

  private cleanRequiredText(value: string | undefined, fieldName: string) {
    const normalized = this.cleanOptionalText(value);
    if (!normalized) {
      throw new BadRequestException(`El campo ${fieldName} es requerido`);
    }
    return normalized;
  }

  private cleanOptionalText(...values: Array<string | null | undefined>) {
    for (const value of values) {
      const normalized = value?.trim();
      if (normalized) return normalized;
    }
    return null;
  }

  private parseOptionalDate(
    primary?: string | null,
    alias?: string | null,
    fieldName = 'date',
  ): Date | null {
    for (const value of [primary, alias]) {
      if (value == null) continue;
      const trimmed = value.trim();
      if (!trimmed) continue;
      const parsed = new Date(trimmed);
      if (Number.isNaN(parsed.getTime())) {
        throw new BadRequestException(`El campo ${fieldName} debe ser una fecha válida`);
      }
      return parsed;
    }

    return null;
  }

  private async runNotificationHook(label: string, action: () => Promise<void>) {
    try {
      await action();
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.logger.error(`Notification hook failed ${label}: ${message}`);
    }
  }

  private toApiStatus(status: ServiceOrderRecord['status']) {
    return SERVICE_ORDER_STATUS_FROM_DB[status];
  }

  private toNumber(
    value: Prisma.Decimal | number | string | null | undefined,
  ): number {
    if (value == null) return 0;
    if (value instanceof Prisma.Decimal) return value.toNumber();
    const numeric = Number(value);
    return Number.isFinite(numeric) ? numeric : 0;
  }

  private buildFinalizedAtRange(from?: string, to?: string): { finalizedAt?: Prisma.DateTimeFilter } {
    if (!from && !to) return {};

    const finalizedAt: Prisma.DateTimeFilter = {};

    if (from) {
      const start = new Date(`${from}T00:00:00.000Z`);
      if (!Number.isNaN(start.getTime())) {
        finalizedAt.gte = start;
      }
    }

    if (to) {
      const end = new Date(`${to}T23:59:59.999Z`);
      if (!Number.isNaN(end.getTime())) {
        finalizedAt.lte = end;
      }
    }

    return Object.keys(finalizedAt).length ? { finalizedAt } : {};
  }

  private toNullableNumber(
    value: Prisma.Decimal | number | string | null | undefined,
  ): number | null {
    if (value == null) return null;
    if (value instanceof Prisma.Decimal) return value.toNumber();
    const numeric = Number(value);
    return Number.isFinite(numeric) ? numeric : null;
  }

  private mapClient(client: Client) {
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

  private mapOrder(item: ServiceOrderWithRelations | ServiceOrderWithClient | ServiceOrderRecord) {
    const base = {
      id: item.id,
      clientId: item.clientId,
      quotationId: item.quotationId,
      category: SERVICE_ORDER_CATEGORY_FROM_DB[item.category],
      serviceType: SERVICE_ORDER_TYPE_FROM_DB[item.serviceType],
      status: SERVICE_ORDER_STATUS_FROM_DB[item.status],
      scheduledFor: item.scheduledFor,
      finalizedAt: item.finalizedAt,
      technicianConfirmedAt: item.technicianConfirmedAt,
      technicianConfirmedById: item.technicianConfirmedById,
      technicalNote: item.technicalNote,
      extraRequirements: item.extraRequirements,
      parentOrderId: item.parentOrderId,
      createdById: item.createdById,
      assignedToId: item.assignedToId,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
      ...('client' in item ? { client: this.mapClient(item.client) } : {}),
    };

    if ('evidences' in item || 'reports' in item) {
      const order = item as ServiceOrderWithRelations;
      return {
        ...base,
        evidences: order.evidences.map((evidence) => this.mapEvidence(evidence)),
        reports: order.reports.map((report) => this.mapReport(report)),
      };
    }

    return base;
  }

  private mapEvidence(item: Prisma.ServiceEvidenceGetPayload<object>) {
    const typeKey = String(item.type ?? '').trim().toUpperCase();
    return {
      id: item.id,
      serviceOrderId: item.serviceOrderId,
      type: SERVICE_EVIDENCE_TYPE_FROM_DB[typeKey] ?? 'referencia_texto',
      content: item.content,
      createdById: item.createdById,
      createdAt: item.createdAt,
    };
  }

  private mapReport(item: Prisma.ServiceReportGetPayload<object>) {
    const typeKey = String(item.type ?? '').trim().toUpperCase();
    return {
      id: item.id,
      serviceOrderId: item.serviceOrderId,
      type: SERVICE_REPORT_TYPE_FROM_DB[typeKey] ?? 'otros',
      report: item.report,
      createdById: item.createdById,
      createdAt: item.createdAt,
    };
  }

  private rethrowWriteError(error: unknown): never {
    if (error instanceof Prisma.PrismaClientKnownRequestError) {
      if (error.code === 'P2025') {
        throw new NotFoundException('El recurso solicitado no existe');
      }
      if (error.code === 'P2003') {
        throw new BadRequestException('La operación viola una relación requerida');
      }
    }

    if (typeof error === 'object' && error !== null) {
      const value = error as { code?: unknown };
      if (value.code === 'P2025') {
        throw new NotFoundException('El recurso solicitado no existe');
      }
      if (value.code === 'P2003') {
        throw new BadRequestException('La operación viola una relación requerida');
      }
    }

    throw error;
  }
}
