import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Prisma, Role, type Client } from '@prisma/client';
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

@Injectable()
export class ServiceOrdersService {
  constructor(private readonly prisma: PrismaService) {}

  async create(user: AuthUser, dto: CreateServiceOrderDto) {
    const payload = await this.buildCreatePayload(user, dto);

    try {
      const created = await this.prisma.serviceOrder.create({
        data: payload,
        include: { client: true },
      });
      return this.mapOrder(created);
    } catch (error) {
      this.rethrowWriteError(error);
    }
  }

  async list(user: AuthUser) {
    const where = await this.buildAccessWhere(user);
    const items = await this.prisma.serviceOrder.findMany({
      where,
      include: { client: true },
      orderBy: [{ createdAt: 'desc' }],
    });
    return { items: items.map((item) => this.mapOrder(item)) };
  }

  async findOne(user: AuthUser, id: string) {
    const item = await this.findOrderWithRelationsOrThrow(user, id);
    return this.mapOrder(item);
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
    this.assertCanModifyOrder(user, item);

    const nextStatus = dto.status as ApiServiceOrderStatus;
    this.assertValidStatusTransition(this.toApiStatus(item.status), nextStatus);

    try {
      const updated = await this.prisma.serviceOrder.update({
        where: { id },
        include: { client: true },
        data: { status: SERVICE_ORDER_STATUS_TO_DB[nextStatus] },
      });
      return this.mapOrder(updated);
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
      return this.mapEvidence(created);
    } catch (error) {
      this.rethrowWriteError(error);
    }
  }

  async addReport(user: AuthUser, id: string, dto: CreateReportDto) {
    const item = await this.findOrderOrThrow(user, id);
    this.assertCanModifyOrder(user, item);
    this.assertTechnicalOutputAccess(user);

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
      return this.mapOrder(cloned);
    } catch (error) {
      this.rethrowWriteError(error);
    }
  }

  async remove(user: AuthUser, id: string) {
    this.assertAdminDelete(user);
    await this.findOrderOrThrow(user, id);

    try {
      await this.prisma.serviceOrder.delete({ where: { id } });
      return { ok: true };
    } catch (error) {
      this.rethrowWriteError(error);
    }
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
      return this.mapOrder(updated);
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

    if (user.role === Role.TECNICO) {
      return {
        OR: [{ assignedToId: user.id }, { createdById: user.id }],
      };
    }

    return { createdById: user.id };
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

      throw new ForbiddenException('Not authorized to access this order');
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
        client: true,
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

      throw new ForbiddenException('Not authorized to access this order');
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
    if (item.createdById === user.id) {
      return;
    }
    if (user.role === Role.TECNICO && item.assignedToId === user.id) {
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

  private toApiStatus(status: ServiceOrderRecord['status']) {
    return SERVICE_ORDER_STATUS_FROM_DB[status];
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
