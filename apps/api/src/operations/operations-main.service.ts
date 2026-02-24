import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import {
  Prisma,
  Role,
  ServiceAssignmentRole,
  ServiceStatus,
  ServiceType,
  ServiceUpdateType,
} from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { ServicesQueryDto } from './dto/services-query.dto';
import { CreateServiceDto } from './dto/create-service.dto';
import { ChangeServiceStatusDto } from './dto/change-service-status.dto';
import { ScheduleServiceDto } from './dto/schedule-service.dto';
import { AssignServiceDto } from './dto/assign-service.dto';
import { ServiceUpdateDto } from './dto/service-update.dto';
import { CreateWarrantyDto } from './dto/create-warranty.dto';

type AuthUser = { id: string; role: Role };

const defaultSteps = [
  { stepKey: 'survey_done', stepLabel: 'Levantamiento completado' },
  { stepKey: 'materials_ready', stepLabel: 'Materiales listos' },
  { stepKey: 'installed', stepLabel: 'Instalación ejecutada' },
  { stepKey: 'tested', stepLabel: 'Pruebas realizadas' },
  { stepKey: 'customer_trained', stepLabel: 'Cliente instruido' },
];

@Injectable()
export class OperationsService {
  constructor(private readonly prisma: PrismaService) {}

  async list(user: AuthUser, query: ServicesQueryDto) {
    const page = query.page && query.page > 0 ? query.page : 1;
    const pageSize = query.pageSize && query.pageSize > 0 ? query.pageSize : 30;
    const skip = (page - 1) * pageSize;

    const where: Prisma.ServiceWhereInput = {
      ...this.scopeWhere(user),
      ...(query.includeDeleted ? {} : { isDeleted: false }),
      ...(query.status ? { status: this.parseStatus(query.status) } : {}),
      ...(query.type ? { serviceType: this.parseType(query.type) } : {}),
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

    const [items, total] = await Promise.all([
      this.prisma.service.findMany({
        where,
        include: this.serviceInclude(),
        orderBy: [{ priority: 'asc' }, { createdAt: 'desc' }],
        skip,
        take: pageSize,
      }),
      this.prisma.service.count({ where }),
    ]);

    return {
      items: items.map((item) => this.normalizeService(item)),
      total,
      page,
      pageSize,
      totalPages: Math.max(1, Math.ceil(total / pageSize)),
    };
  }

  async findOne(user: AuthUser, id: string) {
    const service = await this.prisma.service.findFirst({
      where: { id, ...this.scopeWhere(user), isDeleted: false },
      include: this.serviceInclude(),
    });

    if (!service) throw new NotFoundException('Servicio no encontrado');
    return this.normalizeService(service);
  }

  async create(user: AuthUser, dto: CreateServiceDto) {
    const customer = await this.prisma.client.findUnique({ where: { id: dto.customerId } });
    if (!customer || customer.isDeleted) {
      throw new BadRequestException('Cliente inválido');
    }

    if (dto.serviceType === 'warranty' && !dto.warrantyParentServiceId) {
      throw new BadRequestException('Garantía requiere servicio padre');
    }

    if (dto.warrantyParentServiceId) {
      const parent = await this.prisma.service.findFirst({
        where: { id: dto.warrantyParentServiceId, isDeleted: false },
      });
      if (!parent) throw new BadRequestException('Servicio padre no encontrado');
    }

    const priority = dto.priority ?? (dto.serviceType === 'installation' ? 1 : 2);

    const created = await this.prisma.$transaction(async (tx) => {
      const service = await tx.service.create({
        data: {
          customerId: dto.customerId,
          createdByUserId: user.id,
          serviceType: this.parseType(dto.serviceType),
          category: dto.category.trim(),
          status: ServiceStatus.RESERVED,
          priority,
          title: dto.title.trim(),
          description: dto.description.trim(),
          quotedAmount: dto.quotedAmount,
          depositAmount: dto.depositAmount,
          paymentStatus: dto.paymentStatus ?? 'pending',
          addressSnapshot: dto.addressSnapshot?.trim() || customer.direccion,
          warrantyParentServiceId: dto.warrantyParentServiceId,
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
        },
        include: this.serviceInclude(),
      });

      return service;
    });

    return this.normalizeService(created);
  }

  async changeStatus(user: AuthUser, id: string, dto: ChangeServiceStatusDto) {
    const service = await this.prisma.service.findFirst({
      where: { id, isDeleted: false },
      include: {
        assignments: true,
      },
    });

    if (!service) throw new NotFoundException('Servicio no encontrado');
    this.assertCanOperate(user, service.createdByUserId, service.assignments.map((a) => a.userId));

    const nextStatus = this.parseStatus(dto.status);
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

      return row;
    });

    return this.normalizeService(updated);
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

      return row;
    });

    return {
      ...this.normalizeService(updated),
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

      return tx.service.findUnique({ where: { id }, include: this.serviceInclude() });
    });

    if (!updated) throw new NotFoundException('Servicio no encontrado');
    return this.normalizeService(updated);
  }

  async addUpdate(user: AuthUser, id: string, dto: ServiceUpdateDto) {
    const service = await this.prisma.service.findFirst({
      where: { id, isDeleted: false },
      include: { assignments: true },
    });
    if (!service) throw new NotFoundException('Servicio no encontrado');

    this.assertCanView(user, service.createdByUserId, service.assignments.map((a) => a.userId));

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

      return this.findOne(user, id);
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

    return { ok: true };
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

      return row;
    });

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

    const created = await this.prisma.$transaction(async (tx) => {
      const row = await tx.service.create({
        data: {
          customerId: parent.customerId,
          createdByUserId: user.id,
          serviceType: ServiceType.WARRANTY,
          category: parent.category,
          status: ServiceStatus.WARRANTY,
          priority: 1,
          title: dto.title?.trim() || `Garantía: ${parent.title}`,
          description: dto.description?.trim() || `Garantía derivada del servicio ${parent.id}`,
          paymentStatus: 'pending',
          addressSnapshot: parent.addressSnapshot,
          warrantyParentServiceId: parent.id,
          tags: parent.tags,
          steps: { create: defaultSteps },
        },
        include: this.serviceInclude(),
      });

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

    return this.normalizeService(created);
  }

  async remove(user: AuthUser, id: string) {
    const service = await this.prisma.service.findFirst({ where: { id, isDeleted: false } });
    if (!service) throw new NotFoundException('Servicio no encontrado');

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

    return { ok: true };
  }

  async servicesByCustomer(user: AuthUser, customerId: string) {
    const items = await this.prisma.service.findMany({
      where: {
        customerId,
        isDeleted: false,
        ...this.scopeWhere(user),
      },
      include: this.serviceInclude(),
      orderBy: [{ createdAt: 'desc' }],
    });

    return items.map((item) => this.normalizeService(item));
  }

  async dashboard(user: AuthUser, from?: string, to?: string) {
    const where: Prisma.ServiceWhereInput = {
      ...this.scopeWhere(user),
      isDeleted: false,
      ...this.scheduleRangeWhere(from, to),
    };

    const [byStatus, installationsPendingToday, warrantiesOpen, completedByTech, avgPerStage] = await Promise.all([
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

    const techIds = completedByTech.map((row) => row.userId);
    const techs = techIds.length
      ? await this.prisma.user.findMany({ where: { id: { in: techIds } }, select: { id: true, nombreCompleto: true } })
      : [];
    const techMap = new Map(techs.map((t) => [t.id, t.nombreCompleto]));

    const averageHours = avgPerStage.length
      ? avgPerStage.reduce((acc, row) => {
          if (!row.completedAt) return acc;
          return acc + (row.completedAt.getTime() - row.createdAt.getTime()) / (1000 * 60 * 60);
        }, 0) / avgPerStage.length
      : 0;

    return {
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
  }

  private serviceInclude() {
    return {
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
    };
  }

  private normalizeService(service: any) {
    return {
      ...service,
      serviceType: this.toApiType(service.serviceType),
      status: this.toApiStatus(service.status),
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

  private scopeWhere(user: AuthUser): Prisma.ServiceWhereInput {
    if (user.role === Role.ADMIN || user.role === Role.ASISTENTE) return {};
    if (user.role === Role.VENDEDOR) return { createdByUserId: user.id };
    if (user.role === Role.TECNICO) return { assignments: { some: { userId: user.id } } };
    return { id: '__none__' };
  }

  private assertCanView(user: AuthUser, sellerId: string, assignedIds: string[]) {
    if (user.role === Role.ADMIN || user.role === Role.ASISTENTE) return;
    if (user.role === Role.VENDEDOR && user.id === sellerId) return;
    if (user.role === Role.TECNICO && assignedIds.includes(user.id)) return;
    throw new ForbiddenException('No autorizado para ver este servicio');
  }

  private assertCanOperate(user: AuthUser, sellerId: string, assignedIds: string[]) {
    if (user.role === Role.ADMIN || user.role === Role.ASISTENTE) return;
    if (user.role === Role.TECNICO && assignedIds.includes(user.id)) return;
    if (user.role === Role.VENDEDOR && user.id === sellerId) return;
    throw new ForbiddenException('No autorizado para modificar este servicio');
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
