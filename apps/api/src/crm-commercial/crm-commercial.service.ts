import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';import {
  CrmCommercialCustomerStatus,
  CrmCommercialFollowupTaskPriority,
  CrmCommercialFollowupTaskStatus,
  Prisma,
  Role,
} from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { ChangeCrmCommercialStatusDto } from './dto/change-crm-commercial-status.dto';
import { CreateCrmCommercialActivityDto } from './dto/create-crm-commercial-activity.dto';
import { CreateCrmCommercialCustomerDto } from './dto/create-crm-commercial-customer.dto';
import { CreateCrmCommercialNoteDto } from './dto/create-crm-commercial-note.dto';
import { CrmCommercialQueryDto } from './dto/crm-commercial-query.dto';
import { UpdateCrmCommercialCustomerDto } from './dto/update-crm-commercial-customer.dto';
import { CreateCrmCommercialFollowupTaskDto } from './dto/create-crm-commercial-followup-task.dto';
import { UpdateCrmCommercialFollowupTaskDto } from './dto/update-crm-commercial-followup-task.dto';
import { CrmCommercialFollowupTaskQueryDto } from './dto/crm-commercial-followup-task-query.dto';

type AuthUser = { id: string; role: Role };

@Injectable()
export class CrmCommercialService {
  constructor(private readonly prisma: PrismaService) {}

  private isAdmin(user: AuthUser): boolean {
    return user.role === Role.ADMIN;
  }

  private canWrite(user: AuthUser): boolean {
    // Temporarily restricted to ADMIN only while module is in development.
    // Extend this list when ready to enable other roles.
    return user.role === Role.ADMIN;
  }

  private parseBool(raw?: string): boolean | undefined {
    if (raw == null) return undefined;
    const value = String(raw).trim().toLowerCase();
    if (['1', 'true', 'yes', 'si'].includes(value)) return true;
    if (['0', 'false', 'no'].includes(value)) return false;
    return undefined;
  }

  private normalizeText(value?: string | null): string | undefined {
    if (value == null) return undefined;
    const trimmed = value.trim();
    return trimmed.length === 0 ? undefined : trimmed;
  }

  private normalizePhone(value: string): string {
    return value.trim().replace(/\s+/g, ' ');
  }

  private async ensureClientExists(clientId?: string) {
    if (!clientId) return;
    const client = await this.prisma.client.findUnique({
      where: { id: clientId },
      select: { id: true },
    });
    if (!client) {
      throw new BadRequestException('El cliente principal asociado no existe');
    }
  }

  private async ensureNoDuplicateForCreate(input: {
    nombre: string;
    telefono: string;
    clientId?: string;
  }) {
    if (input.clientId) {
      const byClient = await this.prisma.crmCommercialCustomer.findFirst({
        where: { clientId: input.clientId },
        select: { id: true },
      });
      if (byClient) {
        throw new ConflictException(
          'Ya existe un cliente CRM comercial vinculado a este cliente principal',
        );
      }
    }

    const byNameAndPhone = await this.prisma.crmCommercialCustomer.findFirst({
      where: {
        nombre: { equals: input.nombre, mode: 'insensitive' },
        telefono: input.telefono,
      },
      select: { id: true },
    });
    if (byNameAndPhone) {
      throw new ConflictException(
        'Ya existe un cliente CRM comercial con ese nombre y telefono',
      );
    }
  }

  private async ensureNoDuplicateForUpdate(
    customerId: string,
    input: {
      nombre?: string;
      telefono?: string;
      clientId?: string;
    },
  ) {
    if (input.clientId) {
      const byClient = await this.prisma.crmCommercialCustomer.findFirst({
        where: {
          clientId: input.clientId,
          id: { not: customerId },
        },
        select: { id: true },
      });
      if (byClient) {
        throw new ConflictException(
          'Ese cliente principal ya esta vinculado en CRM comercial',
        );
      }
    }

    if (input.nombre && input.telefono) {
      const byNameAndPhone = await this.prisma.crmCommercialCustomer.findFirst({
        where: {
          id: { not: customerId },
          nombre: { equals: input.nombre, mode: 'insensitive' },
          telefono: input.telefono,
        },
        select: { id: true },
      });
      if (byNameAndPhone) {
        throw new ConflictException(
          'Ya existe un cliente CRM comercial con ese nombre y telefono',
        );
      }
    }
  }

  private async ensureCustomerAccessible(user: AuthUser, customerId: string) {
    const customer = await this.prisma.crmCommercialCustomer.findUnique({
      where: { id: customerId },
      include: {
        responsableUser: {
          select: { id: true, nombreCompleto: true, role: true },
        },
      },
    });

    if (!customer) {
      throw new NotFoundException('Cliente CRM comercial no encontrado');
    }

    if (this.isAdmin(user)) return customer;

    if (user.role === Role.VENDEDOR && customer.responsableUserId !== user.id) {
      throw new ForbiddenException(
        'No tienes acceso a este cliente CRM comercial',
      );
    }

    return customer;
  }

  async create(user: AuthUser, dto: CreateCrmCommercialCustomerDto) {
    if (!this.canWrite(user)) {
      throw new ForbiddenException('No tienes permisos para crear clientes CRM');
    }

    const phone = this.normalizePhone(dto.telefono);
    if (!phone) {
      throw new BadRequestException('Telefono requerido');
    }

    const assignedUserId =
      user.role === Role.VENDEDOR ? user.id : dto.responsableUserId ?? user.id;

    const normalizedName = dto.nombre.trim();
    await this.ensureClientExists(dto.clientId);
    await this.ensureNoDuplicateForCreate({
      nombre: normalizedName,
      telefono: phone,
      clientId: dto.clientId,
    });

    const created = await this.prisma.crmCommercialCustomer.create({
      data: {
        nombre: normalizedName,
        telefono: phone,
        direccion: this.normalizeText(dto.direccion),
        ciudad: this.normalizeText(dto.ciudad),
        etiqueta: this.normalizeText(dto.etiqueta),
        clientId: dto.clientId,
        responsableUserId: assignedUserId,
        estadoActual: dto.estadoActual ?? CrmCommercialCustomerStatus.NUEVO,
        nextAction: this.normalizeText(dto.nextAction),
        nextActionAt: dto.nextActionAt ? new Date(dto.nextActionAt) : null,
        observacion: this.normalizeText(dto.observacion),
        createdByUserId: user.id,
      },
      include: {
        responsableUser: {
          select: { id: true, nombreCompleto: true, role: true },
        },
        createdByUser: {
          select: { id: true, nombreCompleto: true, role: true },
        },
      },
    });

    await this.prisma.crmCommercialStatusHistory.create({
      data: {
        customerId: created.id,
        estadoAnterior: null,
        estadoNuevo: created.estadoActual,
        changedByUserId: user.id,
        nota: 'Registro inicial en CRM comercial',
      },
    });

    return created;
  }

  async findAll(user: AuthUser, query: CrmCommercialQueryDto) {
    const page = Math.max(1, Number(query.page ?? 1));
    const pageSize = Math.min(200, Math.max(1, Number(query.pageSize ?? 20)));
    const skip = (page - 1) * pageSize;

    const andFilters: Prisma.CrmCommercialCustomerWhereInput[] = [];
    if (query.status) {
      andFilters.push({ estadoActual: query.status });
    }
    if (query.responsableUserId) {
      andFilters.push({ responsableUserId: query.responsableUserId });
    }
    if (query.q) {
      andFilters.push({
        OR: [
          { nombre: { contains: query.q, mode: 'insensitive' } },
          { telefono: { contains: query.q, mode: 'insensitive' } },
          { direccion: { contains: query.q, mode: 'insensitive' } },
          { ciudad: { contains: query.q, mode: 'insensitive' } },
        ],
      });
    }

    const onlyMine = this.parseBool(query.onlyMine) ?? false;
    if (!this.isAdmin(user) && user.role === Role.VENDEDOR) {
      andFilters.push({ responsableUserId: user.id });
    } else if (onlyMine) {
      andFilters.push({ responsableUserId: user.id });
    }

    const where: Prisma.CrmCommercialCustomerWhereInput =
      andFilters.length > 0 ? { AND: andFilters } : {};

    const [total, items] = await this.prisma.$transaction([
      this.prisma.crmCommercialCustomer.count({ where }),
      this.prisma.crmCommercialCustomer.findMany({
        where,
        skip,
        take: pageSize,
        orderBy: [{ updatedAt: 'desc' }, { createdAt: 'desc' }],
        include: {
          responsableUser: {
            select: { id: true, nombreCompleto: true, role: true },
          },
          createdByUser: {
            select: { id: true, nombreCompleto: true, role: true },
          },
          client: {
            select: {
              id: true,
              nombre: true,
              telefono: true,
              email: true,
            },
          },
        },
      }),
    ]);

    return {
      page,
      pageSize,
      total,
      totalPages: Math.max(1, Math.ceil(total / pageSize)),
      items,
    };
  }

  async findOne(user: AuthUser, id: string) {
    await this.ensureCustomerAccessible(user, id);

    return this.prisma.crmCommercialCustomer.findUnique({
      where: { id },
      include: {
        responsableUser: {
          select: { id: true, nombreCompleto: true, role: true },
        },
        createdByUser: {
          select: { id: true, nombreCompleto: true, role: true },
        },
        client: {
          select: {
            id: true,
            nombre: true,
            telefono: true,
            email: true,
            direccion: true,
          },
        },
        statusHistory: {
          orderBy: { createdAt: 'desc' },
          take: 120,
          include: {
            changedByUser: {
              select: { id: true, nombreCompleto: true, role: true },
            },
          },
        },
        notes: {
          orderBy: { createdAt: 'desc' },
          take: 120,
          include: {
            authorUser: {
              select: { id: true, nombreCompleto: true, role: true },
            },
          },
        },
        activities: {
          orderBy: { createdAt: 'desc' },
          take: 120,
          include: {
            createdByUser: {
              select: { id: true, nombreCompleto: true, role: true },
            },
            assignedToUser: {
              select: { id: true, nombreCompleto: true, role: true },
            },
          },
        },
      },
    });
  }

  async update(user: AuthUser, id: string, dto: UpdateCrmCommercialCustomerDto) {
    if (!this.canWrite(user)) {
      throw new ForbiddenException('No tienes permisos para editar clientes CRM');
    }

    const current = await this.ensureCustomerAccessible(user, id);

    let assignedUserId = dto.responsableUserId;
    if (user.role === Role.VENDEDOR) {
      assignedUserId = current.responsableUserId ?? user.id;
    }

    const normalizedName = dto.nombre?.trim() ?? current.nombre;
    const normalizedPhone = dto.telefono
      ? this.normalizePhone(dto.telefono)
      : current.telefono;
    const nextClientId = dto.clientId ?? current.clientId ?? undefined;

    await this.ensureClientExists(nextClientId);
    await this.ensureNoDuplicateForUpdate(id, {
      nombre: normalizedName,
      telefono: normalizedPhone,
      clientId: nextClientId,
    });

    const updated = await this.prisma.crmCommercialCustomer.update({
      where: { id },
      data: {
        nombre: dto.nombre?.trim(),
        telefono: dto.telefono ? this.normalizePhone(dto.telefono) : undefined,
        direccion:
          dto.direccion == null ? undefined : this.normalizeText(dto.direccion),
        ciudad: dto.ciudad == null ? undefined : this.normalizeText(dto.ciudad),
        etiqueta:
          dto.etiqueta == null ? undefined : this.normalizeText(dto.etiqueta),
        clientId: dto.clientId,
        responsableUserId: assignedUserId,
        nextActionAt:
          dto.nextActionAt == null ? undefined : new Date(dto.nextActionAt),
        nextAction:
          dto.nextAction == null ? undefined : this.normalizeText(dto.nextAction),
        observacion:
          dto.observacion == null ? undefined : this.normalizeText(dto.observacion),
      },
      include: {
        responsableUser: {
          select: { id: true, nombreCompleto: true, role: true },
        },
        createdByUser: {
          select: { id: true, nombreCompleto: true, role: true },
        },
      },
    });

    return updated;
  }

  async changeStatus(
    user: AuthUser,
    id: string,
    dto: ChangeCrmCommercialStatusDto,
  ) {
    if (!this.canWrite(user)) {
      throw new ForbiddenException('No tienes permisos para cambiar estado');
    }

    const customer = await this.ensureCustomerAccessible(user, id);

    if (customer.estadoActual === dto.status) {
      return this.prisma.crmCommercialCustomer.findUnique({
        where: { id },
        include: {
          responsableUser: {
            select: { id: true, nombreCompleto: true, role: true },
          },
        },
      });
    }

    const updated = await this.prisma.crmCommercialCustomer.update({
      where: { id },
      data: {
        estadoActual: dto.status,
        lastInteractionAt: new Date(),
      },
      include: {
        responsableUser: {
          select: { id: true, nombreCompleto: true, role: true },
        },
      },
    });

    await this.prisma.crmCommercialStatusHistory.create({
      data: {
        customerId: id,
        estadoAnterior: customer.estadoActual,
        estadoNuevo: dto.status,
        changedByUserId: user.id,
        nota: this.normalizeText(dto.note),
      },
    });

    return updated;
  }

  async addNote(user: AuthUser, id: string, dto: CreateCrmCommercialNoteDto) {
    if (!this.canWrite(user)) {
      throw new ForbiddenException('No tienes permisos para agregar notas');
    }

    await this.ensureCustomerAccessible(user, id);

    const note = await this.prisma.crmCommercialNote.create({
      data: {
        customerId: id,
        authorUserId: user.id,
        note: dto.note.trim(),
      },
      include: {
        authorUser: {
          select: { id: true, nombreCompleto: true, role: true },
        },
      },
    });

    await this.prisma.crmCommercialCustomer.update({
      where: { id },
      data: {
        lastInteractionAt: new Date(),
      },
    });

    return note;
  }

  async addActivity(
    user: AuthUser,
    id: string,
    dto: CreateCrmCommercialActivityDto,
  ) {
    if (!this.canWrite(user)) {
      throw new ForbiddenException('No tienes permisos para registrar actividades');
    }

    await this.ensureCustomerAccessible(user, id);

    return this.prisma.crmCommercialActivity.create({
      data: {
        customerId: id,
        createdByUserId: user.id,
        assignedToUserId: dto.assignedToUserId,
        activityType: dto.type.trim(),
        description: dto.description.trim(),
        dueAt: dto.dueAt ? new Date(dto.dueAt) : null,
      },
      include: {
        createdByUser: {
          select: { id: true, nombreCompleto: true, role: true },
        },
        assignedToUser: {
          select: { id: true, nombreCompleto: true, role: true },
        },
      },
    });
  }

  // ─── Phase 2: Follow-up Tasks ─────────────────────────────────────────────

  private taskUserInclude = {
    select: { id: true, nombreCompleto: true, role: true },
  } as const;

  async createFollowupTask(
    user: AuthUser,
    customerId: string,
    dto: CreateCrmCommercialFollowupTaskDto,
  ) {
    await this.ensureCustomerAccessible(user, customerId);

    const task = await this.prisma.crmCommercialFollowupTask.create({
      data: {
        customerId,
        title: dto.title.trim(),
        description: this.normalizeText(dto.description),
        dueDate: dto.dueDate ? new Date(dto.dueDate) : null,
        priority: dto.priority ?? CrmCommercialFollowupTaskPriority.NORMAL,
        assignedUserId: dto.assignedUserId,
        createdByUserId: user.id,
      },
      include: {
        assignedUser: { select: { id: true, nombreCompleto: true, role: true } },
        createdByUser: { select: { id: true, nombreCompleto: true, role: true } },
        completedByUser: { select: { id: true, nombreCompleto: true, role: true } },
      },
    });

    await this.prisma.crmCommercialActivity.create({
      data: {
        customerId,
        createdByUserId: user.id,
        activityType: 'TAREA_CREADA',
        description: `Tarea de seguimiento creada: ${task.title}`,
      },
    });

    return task;
  }

  async listFollowupTasks(
    user: AuthUser,
    query: CrmCommercialFollowupTaskQueryDto,
  ) {
    const now = new Date();
    const andFilters: Prisma.CrmCommercialFollowupTaskWhereInput[] = [];

    if (query.customerId) {
      andFilters.push({ customerId: query.customerId });
    }
    if (query.assignedUserId) {
      andFilters.push({ assignedUserId: query.assignedUserId });
    }
    if (query.priority) {
      andFilters.push({
        priority: query.priority as CrmCommercialFollowupTaskPriority,
      });
    }

    const overdueOnly = this.parseBool(query.overdueOnly) ?? false;
    if (overdueOnly) {
      andFilters.push({
        status: CrmCommercialFollowupTaskStatus.PENDIENTE,
        dueDate: { lt: now },
      });
    } else if (query.status) {
      andFilters.push({
        status: query.status as CrmCommercialFollowupTaskStatus,
      });
    }

    if (query.dueFrom) {
      andFilters.push({ dueDate: { gte: new Date(query.dueFrom) } });
    }
    if (query.dueTo) {
      andFilters.push({ dueDate: { lte: new Date(query.dueTo) } });
    }

    const tasks = await this.prisma.crmCommercialFollowupTask.findMany({
      where: andFilters.length > 0 ? { AND: andFilters } : {},
      include: {
        assignedUser: { select: { id: true, nombreCompleto: true, role: true } },
        createdByUser: { select: { id: true, nombreCompleto: true, role: true } },
        completedByUser: { select: { id: true, nombreCompleto: true, role: true } },
      },
      orderBy: [{ dueDate: 'asc' }, { createdAt: 'desc' }],
    });

    return tasks.map((task) => ({
      ...task,
      effectiveStatus:
        task.status === CrmCommercialFollowupTaskStatus.PENDIENTE &&
        task.dueDate &&
        task.dueDate < now
          ? CrmCommercialFollowupTaskStatus.VENCIDA
          : task.status,
    }));
  }

  async updateFollowupTask(
    user: AuthUser,
    taskId: string,
    dto: UpdateCrmCommercialFollowupTaskDto,
  ) {
    const task = await this.prisma.crmCommercialFollowupTask.findUnique({
      where: { id: taskId },
      select: {
        id: true,
        customerId: true,
        title: true,
        dueDate: true,
        priority: true,
        status: true,
      },
    });
    if (!task) {
      throw new NotFoundException('Tarea de seguimiento no encontrada');
    }

    const updateData: {
      title?: string;
      description?: string | null;
      assignedUserId?: string | null;
      dueDate?: Date;
      priority?: CrmCommercialFollowupTaskPriority;
    } = {};
    const activityParts: string[] = [];

    if (dto.title !== undefined) updateData.title = dto.title.trim();
    if (dto.description !== undefined) {
      updateData.description = this.normalizeText(dto.description) ?? null;
    }
    if (dto.assignedUserId !== undefined) {
      updateData.assignedUserId = dto.assignedUserId || null;
    }
    if (dto.dueDate !== undefined) {
      const newDate = new Date(dto.dueDate);
      if (!task.dueDate || task.dueDate.getTime() !== newDate.getTime()) {
        activityParts.push(
          `Fecha cambiada a ${newDate.toLocaleDateString('es-DO')}`,
        );
      }
      updateData.dueDate = newDate;
    }
    if (dto.priority !== undefined && dto.priority !== task.priority) {
      activityParts.push(`Prioridad cambiada a ${dto.priority}`);
      updateData.priority = dto.priority;
    }

    const updated = await this.prisma.crmCommercialFollowupTask.update({
      where: { id: taskId },
      data: updateData,
      include: {
        assignedUser: { select: { id: true, nombreCompleto: true, role: true } },
        createdByUser: { select: { id: true, nombreCompleto: true, role: true } },
        completedByUser: { select: { id: true, nombreCompleto: true, role: true } },
      },
    });

    if (activityParts.length > 0) {
      await this.prisma.crmCommercialActivity.create({
        data: {
          customerId: task.customerId,
          createdByUserId: user.id,
          activityType: 'TAREA_MODIFICADA',
          description: `Tarea "${updated.title}": ${activityParts.join(', ')}`,
        },
      });
    }

    return updated;
  }

  async completeFollowupTask(user: AuthUser, taskId: string) {
    const task = await this.prisma.crmCommercialFollowupTask.findUnique({
      where: { id: taskId },
      select: { id: true, customerId: true, title: true, status: true },
    });
    if (!task) {
      throw new NotFoundException('Tarea de seguimiento no encontrada');
    }
    if (task.status === CrmCommercialFollowupTaskStatus.COMPLETADA) {
      throw new BadRequestException('La tarea ya está completada');
    }
    if (task.status === CrmCommercialFollowupTaskStatus.CANCELADA) {
      throw new BadRequestException(
        'No se puede completar una tarea cancelada',
      );
    }

    const completed = await this.prisma.crmCommercialFollowupTask.update({
      where: { id: taskId },
      data: {
        status: CrmCommercialFollowupTaskStatus.COMPLETADA,
        completedAt: new Date(),
        completedByUserId: user.id,
      },
      include: {
        assignedUser: { select: { id: true, nombreCompleto: true, role: true } },
        createdByUser: { select: { id: true, nombreCompleto: true, role: true } },
        completedByUser: { select: { id: true, nombreCompleto: true, role: true } },
      },
    });

    await this.prisma.crmCommercialActivity.create({
      data: {
        customerId: task.customerId,
        createdByUserId: user.id,
        activityType: 'TAREA_COMPLETADA',
        description: `Tarea completada: ${task.title}`,
      },
    });

    return completed;
  }

  async cancelFollowupTask(user: AuthUser, taskId: string) {
    const task = await this.prisma.crmCommercialFollowupTask.findUnique({
      where: { id: taskId },
      select: { id: true, customerId: true, title: true, status: true },
    });
    if (!task) {
      throw new NotFoundException('Tarea de seguimiento no encontrada');
    }
    if (task.status === CrmCommercialFollowupTaskStatus.COMPLETADA) {
      throw new BadRequestException(
        'No se puede cancelar una tarea completada',
      );
    }
    if (task.status === CrmCommercialFollowupTaskStatus.CANCELADA) {
      throw new BadRequestException('La tarea ya está cancelada');
    }

    const cancelled = await this.prisma.crmCommercialFollowupTask.update({
      where: { id: taskId },
      data: { status: CrmCommercialFollowupTaskStatus.CANCELADA },
      include: {
        assignedUser: { select: { id: true, nombreCompleto: true, role: true } },
        createdByUser: { select: { id: true, nombreCompleto: true, role: true } },
        completedByUser: { select: { id: true, nombreCompleto: true, role: true } },
      },
    });

    await this.prisma.crmCommercialActivity.create({
      data: {
        customerId: task.customerId,
        createdByUserId: user.id,
        activityType: 'TAREA_CANCELADA',
        description: `Tarea cancelada: ${task.title}`,
      },
    });

    return cancelled;
  }
}
