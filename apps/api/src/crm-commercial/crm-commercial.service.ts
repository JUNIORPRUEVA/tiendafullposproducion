import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import {
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
import { UpdateCrmCommercialSettingsDto } from './dto/update-crm-commercial-settings.dto';
import { WhatsappService } from '../whatsapp/whatsapp.service';
import { normalizeWhatsappPhone } from '../whatsapp-inbox/whatsapp-identity.util';

type AuthUser = { id: string; role: Role };

@Injectable()
export class CrmCommercialService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly whatsappService: WhatsappService,
  ) {}

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

  private parseLimit(raw: string | undefined, fallback: number, max: number) {
    const parsed = Number(raw);
    if (!Number.isFinite(parsed)) return fallback;
    return Math.min(max, Math.max(1, Math.trunc(parsed)));
  }

  private parseDate(raw?: string) {
    if (!raw) return undefined;
    const parsed = new Date(raw);
    if (Number.isNaN(parsed.getTime())) return undefined;
    return parsed;
  }

  private normalizeComparablePhone(value: string | null | undefined) {
    if (!value) return null;
    const byInbox = normalizeWhatsappPhone(value);
    if (byInbox) return byInbox;
    const digits = value.replace(/\D/g, '');
    return digits.length >= 7 ? digits : null;
  }

  private async getSelectedWhatsappInstanceForCrm() {
    const settings = await this.prisma.crmCommercialSetting.upsert({
      where: { id: 'global' },
      create: { id: 'global' },
      update: {},
    });

    const instanceName = settings.selectedWhatsappInstanceName?.trim() ?? '';
    const selectedId = settings.selectedWhatsappInstanceId?.trim() ?? '';

    if (!instanceName && !selectedId) {
      return {
        selectedInstanceId: null as string | null,
        warning: 'Selecciona una instancia para recibir mensajes reales.',
      };
    }

    // Resolve the actual UserWhatsappInstance UUID (stored in whatsapp_conversations.instance_id)
    // Priority: look up by instanceName first (most reliable), fall back to selectedId if it's a UUID
    let resolvedUuid: string | null = null;

    if (instanceName) {
      const waInstance = await this.prisma.userWhatsappInstance.findUnique({
        where: { instanceName },
        select: { id: true },
      });
      resolvedUuid = waInstance?.id ?? null;
    }

    // Fallback: if selectedId looks like a UUID (user instance), use it directly
    if (!resolvedUuid && selectedId && selectedId !== 'company') {
      const waInstance = await this.prisma.userWhatsappInstance.findUnique({
        where: { id: selectedId },
        select: { id: true },
      });
      resolvedUuid = waInstance?.id ?? null;
    }

    if (!resolvedUuid) {
      return {
        selectedInstanceId: null as string | null,
        warning: 'La instancia seleccionada no existe o aún no ha recibido mensajes.',
      };
    }

    return {
      selectedInstanceId: resolvedUuid,
      warning: null as string | null,
    };
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

  async getAvailableWhatsappInstances(user: AuthUser) {
    if (!this.isAdmin(user)) {
      throw new ForbiddenException('Solo ADMIN puede consultar instancias disponibles');
    }

    const instances = await this.whatsappService.listAllInstancesForCrm();
    return instances.map((instance) => ({
      id: String(instance.id),
      instanceName: String(instance.instanceName ?? ''),
      status: String(instance.status ?? 'pending'),
      webhookEnabled: !!instance.webhookEnabled,
      isCompany: !!instance.isCompany,
      userId: instance.userId ? String(instance.userId) : null,
      userName: String(instance.userName ?? ''),
      userRole: instance.userRole ? String(instance.userRole) : null,
      phoneNumber: instance.phoneNumber ? String(instance.phoneNumber) : null,
    }));
  }

  async getSettings(user: AuthUser) {
    if (!this.isAdmin(user)) {
      throw new ForbiddenException('Solo ADMIN puede ver la configuracion CRM Comercial');
    }

    const [settings, instances] = await Promise.all([
      this.prisma.crmCommercialSetting.upsert({
        where: { id: 'global' },
        create: { id: 'global' },
        update: {},
        include: {
          updatedByUser: {
            select: { id: true, nombreCompleto: true, role: true },
          },
        },
      }),
      this.getAvailableWhatsappInstances(user),
    ]);

    const selectedInstance = settings.selectedWhatsappInstanceId
      ? instances.find((instance) => instance.id === settings.selectedWhatsappInstanceId)
      : null;
    const selectedInstanceExists = settings.selectedWhatsappInstanceId
      ? !!selectedInstance
      : true;

    return {
      ...settings,
      selectedInstanceExists,
      selectedInstanceStatus: selectedInstance?.status ?? null,
      selectedInstanceWebhookEnabled: selectedInstance?.webhookEnabled ?? null,
      warning:
        settings.selectedWhatsappInstanceId && !selectedInstanceExists
          ? 'La instancia seleccionada ya no existe o fue eliminada.'
          : null,
      // Preparado para siguiente fase de mensajes reales
      realMessagesReady:
        !!settings.enabled &&
        !!settings.selectedWhatsappInstanceId &&
        selectedInstanceExists,
    };
  }

  async updateSettings(user: AuthUser, dto: UpdateCrmCommercialSettingsDto) {
    if (!this.isAdmin(user)) {
      throw new ForbiddenException('Solo ADMIN puede actualizar la configuracion CRM Comercial');
    }

    const [current, availableInstances] = await Promise.all([
      this.prisma.crmCommercialSetting.upsert({
        where: { id: 'global' },
        create: { id: 'global' },
        update: {},
      }),
      this.getAvailableWhatsappInstances(user),
    ]);

    let selectedId =
      dto.selectedWhatsappInstanceId != null
        ? dto.selectedWhatsappInstanceId.trim()
        : current.selectedWhatsappInstanceId ?? undefined;
    if (selectedId === '') selectedId = undefined;
    const nextEnabled = dto.enabled ?? current.enabled;

    if (selectedId) {
      const found = availableInstances.find((instance) => instance.id === selectedId);
      const isExplicitSelectionChange = dto.selectedWhatsappInstanceId != null;
      if (!found && (isExplicitSelectionChange || nextEnabled)) {
        throw new BadRequestException(
          'La instancia WhatsApp seleccionada no existe o fue eliminada.',
        );
      }
    }

    if (nextEnabled === true && !selectedId) {
      throw new BadRequestException(
        'Debes seleccionar una instancia antes de habilitar CRM Comercial para mensajes reales.',
      );
    }

    const selectedInstance = selectedId
      ? availableInstances.find((instance) => instance.id === selectedId)
      : null;

    const updated = await this.prisma.crmCommercialSetting.upsert({
      where: { id: 'global' },
      create: {
        id: 'global',
        enabled: nextEnabled,
        selectedWhatsappInstanceId: selectedId ?? null,
        selectedWhatsappInstanceName:
          dto.selectedWhatsappInstanceName?.trim() ||
          selectedInstance?.instanceName ||
          current.selectedWhatsappInstanceName ||
          null,
        updatedByUserId: user.id,
      },
      update: {
        ...(dto.enabled != null ? { enabled: dto.enabled } : {}),
        selectedWhatsappInstanceId: selectedId ?? null,
        selectedWhatsappInstanceName:
          dto.selectedWhatsappInstanceName?.trim() ||
          selectedInstance?.instanceName ||
          current.selectedWhatsappInstanceName ||
          null,
        updatedByUserId: user.id,
      },
      include: {
        updatedByUser: {
          select: { id: true, nombreCompleto: true, role: true },
        },
      },
    });

    return this.getSettings(user).then((settings) => ({
      ok: true,
      settings,
      updated,
    }));
  }

  async getConversations(
    user: AuthUser,
    query: { limit?: string; updatedAfter?: string },
  ) {
    if (!this.isAdmin(user)) {
      throw new ForbiddenException('Solo ADMIN puede leer conversaciones de CRM Comercial');
    }

    const selected = await this.getSelectedWhatsappInstanceForCrm();
    if (!selected.selectedInstanceId) {
      return {
        items: [],
        warning: selected.warning,
      };
    }

    const limit = this.parseLimit(query.limit, 60, 200);
    const updatedAfter = this.parseDate(query.updatedAfter);

    const conversations = await this.prisma.whatsappConversation.findMany({
      where: {
        instanceId: selected.selectedInstanceId,
        NOT: [{ remoteJid: { contains: '@g.us' } }],
        ...(updatedAfter
          ? {
              OR: [
                { updatedAt: { gt: updatedAfter } },
                { lastMessageAt: { gt: updatedAfter } },
              ],
            }
          : {}),
      },
      orderBy: [{ lastMessageAt: 'desc' }, { updatedAt: 'desc' }],
      take: limit,
      include: {
        _count: { select: { messages: true } },
        messages: {
          orderBy: { sentAt: 'desc' },
          take: 1,
          select: {
            id: true,
            direction: true,
            messageType: true,
            body: true,
            caption: true,
            sentAt: true,
          },
        },
      },
    });

    const crmCustomers = await this.prisma.crmCommercialCustomer.findMany({
      select: {
        id: true,
        nombre: true,
        telefono: true,
        estadoActual: true,
      },
    });

    const customerByPhone = new Map<
      string,
      { id: string; nombre: string; estadoActual: CrmCommercialCustomerStatus }
    >();
    for (const customer of crmCustomers) {
      const key = this.normalizeComparablePhone(customer.telefono);
      if (!key) continue;
      if (!customerByPhone.has(key)) {
        customerByPhone.set(key, {
          id: customer.id,
          nombre: customer.nombre,
          estadoActual: customer.estadoActual,
        });
      }
    }

    const items = conversations.map((conversation) => {
      const phone = this.normalizeComparablePhone(
        conversation.remotePhone ?? conversation.remoteJid,
      );
      const linked = phone ? customerByPhone.get(phone) : undefined;
      const last = conversation.messages[0] ?? null;
      const contactName =
        (conversation.remoteName ?? '').trim() ||
        (conversation.remotePhone ?? '').trim() ||
        'Nuevo contacto';

      return {
        id: conversation.id,
        instanceId: conversation.instanceId,
        remoteJid: conversation.remoteJid,
        remotePhone: conversation.remotePhone,
        remoteName: conversation.remoteName,
        contactName,
        lastMessageAt: conversation.lastMessageAt,
        unreadCount: conversation.unreadCount,
        messageCount: conversation._count.messages,
        lastMessagePreview: last?.body ?? last?.caption ?? null,
        lastMessageType: last?.messageType ?? null,
        lastMessageDirection: last?.direction ?? null,
        crmCustomerId: linked?.id ?? null,
        crmCustomerName: linked?.nombre ?? null,
        crmCustomerStatus: linked?.estadoActual ?? null,
        isNewContact: !linked,
        canConvertToCrm: !linked,
      };
    });

    return {
      items,
      warning: null,
    };
  }

  async getConversationMessages(
    user: AuthUser,
    conversationId: string,
    query: { limit?: string; before?: string; after?: string },
  ) {
    if (!this.isAdmin(user)) {
      throw new ForbiddenException('Solo ADMIN puede leer mensajes de CRM Comercial');
    }

    const selected = await this.getSelectedWhatsappInstanceForCrm();
    if (!selected.selectedInstanceId) {
      return {
        items: [],
        warning: selected.warning,
      };
    }

    const conversation = await this.prisma.whatsappConversation.findUnique({
      where: { id: conversationId },
      select: {
        id: true,
        instanceId: true,
        remoteJid: true,
        remotePhone: true,
        remoteName: true,
      },
    });

    if (!conversation || conversation.instanceId !== selected.selectedInstanceId) {
      throw new NotFoundException('Conversacion no encontrada para la instancia activa del CRM Comercial');
    }

    const limit = this.parseLimit(query.limit, 120, 300);
    const before = this.parseDate(query.before);
    const after = this.parseDate(query.after);

    const messages = await this.prisma.whatsappMessage.findMany({
      where: {
        conversationId,
        ...(before ? { sentAt: { lt: before } } : {}),
        ...(after ? { sentAt: { gt: after } } : {}),
      },
      orderBy: { sentAt: 'asc' },
      take: limit,
      select: {
        id: true,
        evolutionId: true,
        direction: true,
        messageType: true,
        body: true,
        caption: true,
        mediaUrl: true,
        mediaMimeType: true,
        senderName: true,
        sentAt: true,
      },
    });

    const conversationPhone = this.normalizeComparablePhone(
      conversation.remotePhone ?? conversation.remoteJid,
    );
    let linkedCustomer:
      | {
          id: string;
          nombre: string;
          estadoActual: CrmCommercialCustomerStatus;
        }
      | null = null;
    if (conversationPhone) {
      const candidates = await this.prisma.crmCommercialCustomer.findMany({
        select: {
          id: true,
          nombre: true,
          telefono: true,
          estadoActual: true,
          updatedAt: true,
        },
        orderBy: { updatedAt: 'desc' },
      });
      for (const candidate of candidates) {
        const key = this.normalizeComparablePhone(candidate.telefono);
        if (key == conversationPhone) {
          linkedCustomer = {
            id: candidate.id,
            nombre: candidate.nombre,
            estadoActual: candidate.estadoActual,
          };
          break;
        }
      }
    }

    return {
      conversation: {
        id: conversation.id,
        remoteJid: conversation.remoteJid,
        remotePhone: conversation.remotePhone,
        remoteName: conversation.remoteName,
        contactName:
          (conversation.remoteName ?? '').trim() ||
          (conversation.remotePhone ?? '').trim() ||
          'Nuevo contacto',
        crmCustomerId: linkedCustomer?.id ?? null,
        crmCustomerName: linkedCustomer?.nombre ?? null,
        crmCustomerStatus: linkedCustomer?.estadoActual ?? null,
        isNewContact: !linkedCustomer,
        canConvertToCrm: !linkedCustomer,
      },
      items: messages,
      warning: null,
    };
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
