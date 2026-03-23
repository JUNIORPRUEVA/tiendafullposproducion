import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Prisma, Role } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
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
  SERVICE_EVIDENCE_TYPE_FROM_DB,
  SERVICE_EVIDENCE_TYPE_TO_DB,
  SERVICE_ORDER_ALLOWED_STATUS_TRANSITIONS,
  SERVICE_ORDER_CATEGORY_FROM_DB,
  SERVICE_ORDER_CATEGORY_TO_DB,
  SERVICE_ORDER_STATUS_FROM_DB,
  SERVICE_ORDER_STATUS_TO_DB,
  SERVICE_ORDER_TYPE_FROM_DB,
  SERVICE_ORDER_TYPE_TO_DB,
} from './service-orders.constants';

type AuthUser = { id: string; role: Role };

type ServiceOrderWithRelations = Prisma.ServiceOrderGetPayload<{
  include: {
    evidences: { orderBy: { createdAt: 'asc' } };
    reports: { orderBy: { createdAt: 'asc' } };
  };
}>;

type ServiceOrderRecord = Prisma.ServiceOrderGetPayload<object>;

@Injectable()
export class ServiceOrdersService {
  constructor(private readonly prisma: PrismaService) {}

  async create(user: AuthUser, dto: CreateServiceOrderDto) {
    const payload = await this.buildCreatePayload(user, dto);

    try {
      const created = await this.prisma.serviceOrder.create({ data: payload });
      return this.mapOrder(created);
    } catch (error) {
      this.rethrowWriteError(error);
    }
  }

  async list(user: AuthUser) {
    const where = await this.buildAccessWhere(user);
    const items = await this.prisma.serviceOrder.findMany({
      where,
      orderBy: [{ createdAt: 'desc' }],
    });
    return { items: items.map((item) => this.mapOrder(item)) };
  }

  async findOne(user: AuthUser, id: string) {
    const item = await this.findOrderWithRelationsOrThrow(user, id);
    return this.mapOrder(item);
  }

  async update(user: AuthUser, id: string, dto: UpdateServiceOrderDto) {
    this.assertAdmin(user);
    const current = await this.findOrderOrThrow(user, id);

    const clientId = this.cleanOptionalText(dto.clientId, dto.client_id) ?? current.clientId;
    const quotationId = this.cleanOptionalText(dto.quotationId, dto.quotation_id) ?? current.quotationId;
    const category = this.cleanOptionalText(dto.category) as ApiServiceOrderCategory | null;
    const serviceType = this.cleanOptionalText(dto.serviceType, dto.service_type) as ApiServiceOrderType | null;
    const technicalNote = this.cleanOptionalText(dto.technicalNote, dto.technical_note);
    const extraRequirements = this.cleanOptionalText(dto.extraRequirements, dto.extra_requirements);
    const assignedToId = this.hasAssignedToInput(dto)
      ? await this.resolveAssignedToId(dto.assignedToId, dto.assigned_to)
      : current.assignedToId;

    await this.assertClientExists(clientId);
    await this.assertQuotationMatchesClient(quotationId, clientId);

    try {
      const updated = await this.prisma.serviceOrder.update({
        where: { id },
        data: {
          clientId,
          quotationId,
          category: category
            ? SERVICE_ORDER_CATEGORY_TO_DB[category]
            : current.category,
          serviceType: serviceType
            ? SERVICE_ORDER_TYPE_TO_DB[serviceType]
            : current.serviceType,
          technicalNote: this.hasTextInput(dto, 'technicalNote', 'technical_note')
            ? technicalNote
            : current.technicalNote,
          extraRequirements: this.hasTextInput(dto, 'extraRequirements', 'extra_requirements')
            ? extraRequirements
            : current.extraRequirements,
          assignedToId,
        },
      });
      return this.mapOrder(updated);
    } catch (error) {
      this.rethrowWriteError(error);
    }
  }

  async updateStatus(user: AuthUser, id: string, dto: UpdateStatusDto) {
    const item = await this.findOrderOrThrow(user, id);
    this.assertCanOperate(user, item);

    const nextStatus = dto.status as ApiServiceOrderStatus;
    this.assertValidStatusTransition(this.toApiStatus(item.status), nextStatus);

    try {
      const updated = await this.prisma.serviceOrder.update({
        where: { id },
        data: { status: SERVICE_ORDER_STATUS_TO_DB[nextStatus] },
      });
      return this.mapOrder(updated);
    } catch (error) {
      this.rethrowWriteError(error);
    }
  }

  async addEvidence(user: AuthUser, id: string, dto: CreateEvidenceDto) {
    const item = await this.findOrderOrThrow(user, id);
    this.assertCanOperate(user, item);
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
      return this.mapEvidence(created);
    } catch (error) {
      this.rethrowWriteError(error);
    }
  }

  async addReport(user: AuthUser, id: string, dto: CreateReportDto) {
    const item = await this.findOrderOrThrow(user, id);
    this.assertCanOperate(user, item);
    this.assertCanManageTechnicalOutputs(user);

    const report = this.cleanRequiredText(dto.report, 'report');

    try {
      const created = await this.prisma.serviceReport.create({
        data: {
          serviceOrderId: item.id,
          report,
          createdById: user.id,
        },
      });
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
      return this.mapOrder(cloned);
    } catch (error) {
      this.rethrowWriteError(error);
    }
  }

  async remove(user: AuthUser, id: string) {
    this.assertAdmin(user);
    await this.findOrderOrThrow(user, id);

    try {
      await this.prisma.serviceOrder.delete({ where: { id } });
      return { ok: true };
    } catch (error) {
      this.rethrowWriteError(error);
    }
  }

  private async buildCreatePayload(
    user: AuthUser,
    dto: CreateServiceOrderDto,
  ): Promise<Prisma.ServiceOrderUncheckedCreateInput> {
    const clientId = this.requireAliasValue(dto.clientId, dto.client_id, 'client_id');
    const quotationId = this.requireAliasValue(dto.quotationId, dto.quotation_id, 'quotation_id');
    const category = this.requireDirectValue(dto.category, 'category') as ApiServiceOrderCategory;
    const serviceType = this.requireAliasValue(dto.serviceType, dto.service_type, 'service_type') as ApiServiceOrderType;
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
      technicalNote,
      extraRequirements,
      createdById: user.id,
      assignedToId,
    };
  }

  private async buildAccessWhere(user: AuthUser): Promise<Prisma.ServiceOrderWhereInput> {
    if (user.role === Role.ADMIN || user.role === Role.ASISTENTE) {
      return {};
    }

    if (user.role === Role.VENDEDOR) {
      return { createdById: user.id };
    }

    if (user.role === Role.TECNICO) {
      const canViewAll = await this.canTechnicianViewAllServices();
      if (canViewAll) return {};
      return {
        OR: [{ assignedToId: user.id }, { createdById: user.id }],
      };
    }

    return { createdById: user.id };
  }

  private async canTechnicianViewAllServices() {
    try {
      const appConfig = await this.prisma.appConfig.findUnique({
        where: { id: 'global' },
        select: { operationsTechCanViewAllServices: true },
      });
      if (appConfig == null) {
        return true;
      }
      return appConfig.operationsTechCanViewAllServices !== false;
    } catch {
      return true;
    }
  }

  private async findOrderOrThrow(
    user: AuthUser,
    id: string,
  ): Promise<ServiceOrderRecord> {
    const where = await this.buildAccessWhere(user);
    const item = await this.prisma.serviceOrder.findFirst({
      where: { id, ...where },
    });

    if (!item) {
      const exists = await this.prisma.serviceOrder.findUnique({
        where: { id },
        select: { id: true },
      });

      if (!exists) {
        throw new NotFoundException('Orden de servicio no encontrada');
      }

      throw new ForbiddenException('No tienes acceso a esta orden de servicio');
    }

    return item;
  }

  private async findOrderWithRelationsOrThrow(
    user: AuthUser,
    id: string,
  ): Promise<ServiceOrderWithRelations> {
    const where = await this.buildAccessWhere(user);
    const item = await this.prisma.serviceOrder.findFirst({
      where: { id, ...where },
      include: {
        evidences: { orderBy: { createdAt: 'asc' } },
        reports: { orderBy: { createdAt: 'asc' } },
      },
    });

    if (!item) {
      const exists = await this.prisma.serviceOrder.findUnique({
        where: { id },
        select: { id: true },
      });

      if (!exists) {
        throw new NotFoundException('Orden de servicio no encontrada');
      }

      throw new ForbiddenException('No tienes acceso a esta orden de servicio');
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
    if (user.role === Role.TECNICO && (item.assignedToId === user.id || item.createdById === user.id)) return;
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

  private hasTextInput(dto: UpdateServiceOrderDto, ...keys: Array<keyof UpdateServiceOrderDto>) {
    return keys.some((key) => Object.prototype.hasOwnProperty.call(dto, key));
  }

  private assertCanAddEvidenceType(user: AuthUser, type: ApiServiceEvidenceType) {
    if (type.startsWith('referencia_')) {
      return;
    }

    this.assertCanManageTechnicalOutputs(user);
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

  private toApiStatus(status: ServiceOrderRecord['status']) {
    return SERVICE_ORDER_STATUS_FROM_DB[status];
  }

  private mapOrder(item: ServiceOrderWithRelations | ServiceOrderRecord) {
    const base = {
      id: item.id,
      clientId: item.clientId,
      quotationId: item.quotationId,
      category: SERVICE_ORDER_CATEGORY_FROM_DB[item.category],
      serviceType: SERVICE_ORDER_TYPE_FROM_DB[item.serviceType],
      status: SERVICE_ORDER_STATUS_FROM_DB[item.status],
      technicalNote: item.technicalNote,
      extraRequirements: item.extraRequirements,
      parentOrderId: item.parentOrderId,
      createdById: item.createdById,
      assignedToId: item.assignedToId,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
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
    return {
      id: item.id,
      serviceOrderId: item.serviceOrderId,
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