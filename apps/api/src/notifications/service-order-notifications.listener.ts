import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { Prisma, Role, ServiceOrderStatus, ServiceOrderType } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationsService } from './notifications.service';
import { ServiceOrderQuotationPdfService } from './service-order-quotation-pdf.service';

type ServiceOrderNotificationContext = Prisma.ServiceOrderGetPayload<{
  include: {
    client: true;
    quotation: {
      include: {
        items: {
          orderBy: {
            createdAt: 'asc';
          };
        };
      };
    };
    createdBy: {
      select: {
        id: true;
        nombreCompleto: true;
        telefono: true;
        numeroFlota: true;
        blocked: true;
      };
    };
    assignedTo: {
      select: {
        id: true;
        nombreCompleto: true;
        telefono: true;
        numeroFlota: true;
        blocked: true;
      };
    };
    reports: {
      orderBy: {
        createdAt: 'asc';
      };
    };
  };
}>;

type InternalRecipient = {
  userId: string;
  name: string;
  numbers: string[];
};

@Injectable()
export class ServiceOrderNotificationsListener {
  private readonly logger = new Logger(ServiceOrderNotificationsListener.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly notifications: NotificationsService,
    private readonly quotationPdf: ServiceOrderQuotationPdfService,
  ) {}

  async handleOrderCreated(orderId: string) {
    await this.scheduleThirtyMinuteReminder(orderId);
    await this.scheduleFifteenMinutePendingReminders(orderId);
  }

  async handleOrderUpdated(orderId: string) {
    await this.scheduleThirtyMinuteReminder(orderId);
  }

  async handleOrderDeleted(orderId: string) {
    await this.cancelPendingReminderJobs(orderId, 'Orden eliminada');
  }

  async handleOrderConfirmed(orderId: string, technicianId: string) {
    const order = await this.loadContext(orderId);
    const technician = order.assignedTo;
    if (!technician || technician.id !== technicianId) {
      throw new NotFoundException('Técnico confirmado no encontrado en la orden');
    }

    const recipients = this.collectCreatorRecipients(order);
    if (!recipients.length) {
      this.logger.warn(`No creator recipients found for confirmation order=${order.id}`);
      return;
    }

    const message = [
      '*Técnico confirmado*',
      `Técnico: ${technician.nombreCompleto}`,
      `Cliente: ${order.client.nombre}`,
      `Teléfono cliente: ${order.client.telefono}`,
      `Servicio: ${this.formatServiceLabel(order)}`,
      `Detalle: ${this.orderDetails(order)}`,
      'El técnico confirmó en la app y puede continuar con el servicio.',
    ].join('\n');

    for (const recipient of recipients) {
      await this.notifications.enqueueWhatsAppRawText({
        toNumber: recipient,
        messageText: message,
        dedupeKey: `service-order:confirm:${order.id}:${technician.id}:${recipient}`,
        payload: {
          kind: 'service_order_confirmation',
          orderId: order.id,
          technicianId: technician.id,
          creatorId: order.createdBy.id,
        },
      });
    }
  }

  async handleStatusChanged(orderId: string, previousStatus: string, nextStatus: string) {
    if (nextStatus === 'en_proceso' || nextStatus === 'finalizado' || nextStatus === 'cancelado') {
      await this.cancelPendingReminderJobs(orderId, `Estado actualizado a ${nextStatus}`);
      await this.cancelFifteenMinuteReminderJobs(orderId, `Estado actualizado a ${nextStatus}`);
    }

    if (nextStatus === 'en_proceso') {
      await this.notifyServiceStarted(orderId);
      return;
    }

    if (nextStatus === 'finalizado') {
      await this.notifyServiceFinalized(orderId);
      return;
    }

    this.logger.debug(`No notification flow for service-order status change ${previousStatus} -> ${nextStatus} order=${orderId}`);
  }

  async dispatchThirtyMinuteReminder(jobId: string) {
    const job = await this.prisma.serviceOrderNotificationJob.findUnique({
      where: { id: jobId },
    });

    if (!job) {
      throw new NotFoundException('Job de notificación no encontrado');
    }

    const order = await this.loadContext(job.orderId);
    if (!order.scheduledFor) {
      await this.markJobCancelled(job.id, 'La orden no tiene fecha programada');
      return;
    }

    if (order.status === ServiceOrderStatus.CANCELADO || order.status === ServiceOrderStatus.FINALIZADO) {
      await this.markJobCancelled(job.id, `La orden ya no es notificable (${order.status})`);
      return;
    }

    const payloadScheduledFor = this.extractScheduledFor(job.payload);
    if (payloadScheduledFor && payloadScheduledFor !== order.scheduledFor.toISOString()) {
      await this.markJobCancelled(job.id, 'La fecha programada cambió y el job quedó obsoleto');
      return;
    }

    const technicians = await this.getRoleRecipients(Role.TECNICO, { fleetOnly: true, fallbackToPhone: true });
    if (!technicians.length) {
      this.logger.warn(`No technician recipients found for 30-minute reminder order=${order.id}`);
      return;
    }

    const message = [
      '*Servicio en 30 minutos*',
      `Cliente: ${order.client.nombre}`,
      `Teléfono cliente: ${order.client.telefono}`,
      `Ubicación: ${this.mapsLink(order)}`,
      `Servicio: ${this.formatServiceLabel(order)}`,
      `Detalle: ${this.orderDetails(order)}`,
      `Programado para: ${order.scheduledFor.toLocaleString('es-DO')}`,
      'Abre la app y confirma la orden para tomar el servicio.',
    ].join('\n');

    for (const technician of technicians) {
      for (const number of technician.numbers) {
        await this.notifications.enqueueWhatsAppRawText({
          toNumber: number,
          messageText: message,
          dedupeKey: `service-order:30m:${order.id}:${order.scheduledFor.toISOString()}:${technician.userId}:${number}`,
          payload: {
            kind: 'service_order_thirty_minutes_before',
            jobId: job.id,
            orderId: order.id,
            scheduledFor: order.scheduledFor.toISOString(),
            recipientUserId: technician.userId,
          },
        });
      }
    }
  }

  async scheduleThirtyMinuteReminder(orderId: string) {
    const order = await this.prisma.serviceOrder.findUnique({
      where: { id: orderId },
      select: {
        id: true,
        status: true,
        scheduledFor: true,
      },
    });

    if (!order) {
      return;
    }

    await this.cancelPendingReminderJobs(order.id, 'Reprogramando notificación de 30 minutos');

    if (!order.scheduledFor) {
      return;
    }

    if (order.status === ServiceOrderStatus.CANCELADO || order.status === ServiceOrderStatus.FINALIZADO) {
      return;
    }

    const runAt = new Date(order.scheduledFor.getTime() - 30 * 60_000);
    const nextRunAt = runAt.getTime() <= Date.now() ? new Date() : runAt;
    const dedupeKey = `service-order:job:30m:${order.id}:${order.scheduledFor.toISOString()}`;

    await this.prisma.serviceOrderNotificationJob.create({
      data: {
        orderId: order.id,
        kind: 'THIRTY_MINUTES_BEFORE',
        status: 'PENDING',
        dedupeKey,
        runAt: nextRunAt,
        payload: {
          scheduledFor: order.scheduledFor.toISOString(),
        },
      },
    }).catch(async (error: unknown) => {
      const code = typeof error === 'object' && error && 'code' in error ? String((error as { code?: unknown }).code ?? '') : '';
      if (code === 'P2002') {
        await this.prisma.serviceOrderNotificationJob.update({
          where: { dedupeKey },
          data: {
            status: 'PENDING',
            runAt: nextRunAt,
            payload: {
              scheduledFor: order.scheduledFor?.toISOString() ?? null,
            },
            attempts: 0,
            lockedAt: null,
            lockedBy: null,
            lastError: null,
            completedAt: null,
          },
        });
        return;
      }
      throw error;
    });
  }

  async dispatchFifteenMinutePending(jobId: string) {
    const job = await this.prisma.serviceOrderNotificationJob.findUnique({
      where: { id: jobId },
    });

    if (!job) {
      throw new NotFoundException('Job de notificación no encontrado');
    }

    const order = await this.loadContext(job.orderId);

    // Si la orden ya no está en pendiente, cancelar el trabajo
    if (order.status !== ServiceOrderStatus.PENDIENTE) {
      await this.markJobCancelled(job.id, `La orden ya cambió de estado (${order.status})`);
      return;
    }

    const technicians = await this.getRoleRecipients(Role.TECNICO, { fleetOnly: true, fallbackToPhone: true });
    if (!technicians.length) {
      this.logger.warn(`No technician recipients found for 15-minute pending reminder order=${order.id}`);
      return;
    }

    const message = [
      '*¡Nuevo servicio disponible!*',
      `Cliente: ${order.client.nombre}`,
      `Teléfono cliente: ${order.client.telefono}`,
      `Ubicación: ${this.mapsLink(order)}`,
      `Servicio: ${this.formatServiceLabel(order)}`,
      `Detalle: ${this.orderDetails(order)}`,
      order.scheduledFor ? `Programado para: ${order.scheduledFor.toLocaleString('es-DO')}` : 'Sin hora programada',
      'Abre la app y toma la orden para iniciar el servicio.',
    ].join('\n');

    for (const technician of technicians) {
      for (const number of technician.numbers) {
        await this.notifications.enqueueWhatsAppRawText({
          toNumber: number,
          messageText: message,
          dedupeKey: `service-order:15m-pending:${order.id}:${job.runAt.toISOString()}:${technician.userId}:${number}`,
          payload: {
            kind: 'service_order_fifteen_minutes_pending',
            jobId: job.id,
            orderId: order.id,
            scheduledFor: order.scheduledFor?.toISOString(),
            recipientUserId: technician.userId,
          },
        });
      }
    }

    // Programar el siguiente trabajo para 15 minutos después
    const nextRunAt = new Date(Date.now() + 15 * 60_000);
    const nextDedupeKey = `service-order:job:15m-pending:${order.id}:run-${nextRunAt.toISOString()}`;

    await this.prisma.serviceOrderNotificationJob.create({
      data: {
        orderId: order.id,
        kind: 'FIFTEEN_MINUTES_PENDING',
        status: 'PENDING',
        dedupeKey: nextDedupeKey,
        runAt: nextRunAt,
        payload: {
          createdFrom: job.id,
        },
      },
    }).catch(async (error: unknown) => {
      const code = typeof error === 'object' && error && 'code' in error ? String((error as { code?: unknown }).code ?? '') : '';
      if (code === 'P2002') {
        // Duplo detectado, actualizar con nueva fecha
        await this.prisma.serviceOrderNotificationJob.update({
          where: { dedupeKey: nextDedupeKey },
          data: {
            status: 'PENDING',
            runAt: nextRunAt,
            attempts: 0,
            lockedAt: null,
            lockedBy: null,
            lastError: null,
            completedAt: null,
          },
        });
        return;
      }
      this.logger.error(`Error creando siguiente job de 15 min para orden ${order.id}:`, error);
    });
  }

  async scheduleFifteenMinutePendingReminders(orderId: string) {
    const order = await this.prisma.serviceOrder.findUnique({
      where: { id: orderId },
      select: {
        id: true,
        status: true,
      },
    });

    if (!order) {
      return;
    }

    // Solo programar si la orden está en estado PENDIENTE
    if (order.status !== ServiceOrderStatus.PENDIENTE) {
      return;
    }

    const runAt = new Date();
    const dedupeKey = `service-order:job:15m-pending:${order.id}:initial`;

    await this.prisma.serviceOrderNotificationJob.create({
      data: {
        orderId: order.id,
        kind: 'FIFTEEN_MINUTES_PENDING',
        status: 'PENDING',
        dedupeKey,
        runAt,
        payload: {
          isInitial: true,
        },
      },
    }).catch(async (error: unknown) => {
      const code = typeof error === 'object' && error && 'code' in error ? String((error as { code?: unknown }).code ?? '') : '';
      if (code === 'P2002') {
        await this.prisma.serviceOrderNotificationJob.update({
          where: { dedupeKey },
          data: {
            status: 'PENDING',
            runAt,
            attempts: 0,
            lockedAt: null,
            lockedBy: null,
            lastError: null,
            completedAt: null,
          },
        });
        return;
      }
      throw error;
    });
  }

  private async notifyServiceStarted(orderId: string) {
    const order = await this.loadContext(orderId);
    const isInvoiceFlow = this.requiresAssistantInvoiceFlow(order.serviceType);
    const creatorRecipients = this.collectCreatorRecipients(order);

    const baseMessage = [
      '*Servicio iniciado*',
      `Cliente: ${order.client.nombre}`,
      `Teléfono cliente: ${order.client.telefono}`,
      `Ubicación: ${this.mapsLink(order)}`,
      `Servicio: ${this.formatServiceLabel(order)}`,
      `Detalle: ${this.orderDetails(order)}`,
      isInvoiceFlow
        ? 'Preparar factura y enviarla inmediatamente después de la finalización.'
        : 'El servicio cambió a EN PROCESO.',
    ].join('\n');

    if (!isInvoiceFlow) {
      for (const recipient of creatorRecipients) {
        await this.notifications.enqueueWhatsAppRawText({
          toNumber: recipient,
          messageText: baseMessage,
          dedupeKey: `service-order:start:${order.id}:${recipient}`,
          payload: {
            kind: 'service_order_started',
            orderId: order.id,
            recipient: recipient,
          },
        });
      }
      return;
    }

    const assistants = await this.getRoleRecipients(Role.ASISTENTE, { fleetOnly: false, fallbackToPhone: true });
    if (!assistants.length) {
      this.logger.warn(`No assistant recipients found for service started order=${order.id}`);
      return;
    }

    const pdf = await this.quotationPdf.buildForOrder(order.id);

    for (const assistant of assistants) {
      for (const number of assistant.numbers) {
        await this.notifications.enqueueWhatsAppDocument({
          toNumber: number,
          messageText: baseMessage,
          dedupeKey: `service-order:start:${order.id}:${assistant.userId}:${number}`,
          payload: {
            kind: 'service_order_started_with_quote',
            orderId: order.id,
            recipientUserId: assistant.userId,
          },
          fileName: pdf.fileName,
          bytes: pdf.bytes,
          recipientUserId: assistant.userId,
        });
      }
    }
  }

  private async notifyServiceFinalized(orderId: string) {
    const order = await this.loadContext(orderId);
    const isInvoiceFlow = this.requiresAssistantInvoiceFlow(order.serviceType);
    const creatorRecipients = this.collectCreatorRecipients(order);

    const extraDetails = [order.extraRequirements?.trim(), order.technicalNote?.trim()]
      .filter((item): item is string => !!item)
      .join(' | ');
    const customerComments = this.customerComments(order);

    const baseMessage = [
      '*Servicio completado*',
      `Cliente: ${order.client.nombre}`,
      `Servicio: ${this.formatServiceLabel(order)}`,
      `Detalle: ${this.orderDetails(order)}`,
      extraDetails ? `Detalles extra: ${extraDetails}` : null,
      customerComments ? `Comentarios cliente: ${customerComments}` : null,
      isInvoiceFlow
        ? 'Enviar factura inmediatamente. El técnico está esperando.'
        : 'La orden fue finalizada con éxito.',
    ].filter(Boolean).join('\n');

    if (!isInvoiceFlow) {
      for (const recipient of creatorRecipients) {
        await this.notifications.enqueueWhatsAppRawText({
          toNumber: recipient,
          messageText: baseMessage,
          dedupeKey: `service-order:finalized:${order.id}:${recipient}`,
          payload: {
            kind: 'service_order_finalized',
            orderId: order.id,
            recipient: recipient,
          },
        });
      }
      return;
    }

    const assistants = await this.getRoleRecipients(Role.ASISTENTE, { fleetOnly: false, fallbackToPhone: true });
    const assistantNumbers = assistants.flatMap((assistant) => assistant.numbers);
    const recipients = [...new Set([...assistantNumbers, ...creatorRecipients])];

    for (const recipient of recipients) {
      await this.notifications.enqueueWhatsAppRawText({
        toNumber: recipient,
        messageText: baseMessage,
        dedupeKey: `service-order:finalized:${order.id}:${recipient}`,
        payload: {
          kind: 'service_order_finalized_invoice_flow',
          orderId: order.id,
          recipient: recipient,
        },
      });
    }
  }

  private async loadContext(orderId: string): Promise<ServiceOrderNotificationContext> {
    const order = await this.prisma.serviceOrder.findUnique({
      where: { id: orderId },
      include: {
        client: true,
        quotation: {
          include: {
            items: {
              orderBy: {
                createdAt: 'asc',
              },
            },
          },
        },
        createdBy: {
          select: {
            id: true,
            nombreCompleto: true,
            telefono: true,
            numeroFlota: true,
            blocked: true,
          },
        },
        assignedTo: {
          select: {
            id: true,
            nombreCompleto: true,
            telefono: true,
            numeroFlota: true,
            blocked: true,
          },
        },
        reports: {
          orderBy: {
            createdAt: 'asc',
          },
        },
      },
    });

    if (!order) {
      throw new NotFoundException('Orden de servicio no encontrada');
    }

    return order;
  }

  private requiresAssistantInvoiceFlow(serviceType: ServiceOrderType) {
    return serviceType === ServiceOrderType.INSTALACION || serviceType === ServiceOrderType.MANTENIMIENTO;
  }

  private orderDetails(order: ServiceOrderNotificationContext) {
    return [order.technicalNote?.trim(), order.extraRequirements?.trim()]
      .filter((item): item is string => !!item)
      .join(' | ') || 'Sin detalles adicionales';
  }

  private customerComments(order: ServiceOrderNotificationContext) {
    return order.reports
      .filter((report) => report.type === 'REQUERIMIENTO_CLIENTE' || report.type === 'OTROS')
      .map((report) => report.report.trim())
      .filter((report) => report.length > 0)
      .join(' | ');
  }

  private formatServiceLabel(order: ServiceOrderNotificationContext) {
    return `${order.serviceType.toLowerCase()} / ${order.category.toLowerCase()}`;
  }

  private mapsLink(order: ServiceOrderNotificationContext) {
    if (order.client.locationUrl?.trim()) {
      return order.client.locationUrl.trim();
    }

    const lat = this.toNullableNumber(order.client.latitude);
    const lng = this.toNullableNumber(order.client.longitude);
    if (lat == null || lng == null) {
      return 'Ubicación no registrada';
    }

    return `https://maps.google.com/?q=${lat},${lng}`;
  }

  private toNullableNumber(value: Prisma.Decimal | number | string | null | undefined) {
    if (value == null) return null;
    if (value instanceof Prisma.Decimal) return value.toNumber();
    const numeric = Number(value);
    return Number.isFinite(numeric) ? numeric : null;
  }

  private collectCreatorRecipients(order: ServiceOrderNotificationContext) {
    const values = [order.createdBy.numeroFlota, order.createdBy.telefono]
      .map((item) => (item ?? '').trim())
      .filter((item) => item.length > 0);
    return [...new Set(values)];
  }

  private extractScheduledFor(payload: Prisma.JsonValue | null) {
    if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
      return null;
    }
    const raw = (payload as Record<string, unknown>).scheduledFor;
    return typeof raw === 'string' && raw.trim().length > 0 ? raw.trim() : null;
  }

  private async cancelPendingReminderJobs(orderId: string, reason: string) {
    await this.prisma.serviceOrderNotificationJob.updateMany({
      where: {
        orderId,
        kind: 'THIRTY_MINUTES_BEFORE',
        status: { in: ['PENDING', 'PROCESSING'] },
      },
      data: {
        status: 'CANCELLED',
        lockedAt: null,
        lockedBy: null,
        lastError: reason,
      },
    });
  }

  private async cancelFifteenMinuteReminderJobs(orderId: string, reason: string) {
    await this.prisma.serviceOrderNotificationJob.updateMany({
      where: {
        orderId,
        kind: 'FIFTEEN_MINUTES_PENDING',
        status: { in: ['PENDING', 'PROCESSING'] },
      },
      data: {
        status: 'CANCELLED',
        lockedAt: null,
        lockedBy: null,
        lastError: reason,
      },
    });
  }

  private async markJobCancelled(jobId: string, reason: string) {
    await this.prisma.serviceOrderNotificationJob.update({
      where: { id: jobId },
      data: {
        status: 'CANCELLED',
        lockedAt: null,
        lockedBy: null,
        lastError: reason,
      },
    });
  }

  private async getRoleRecipients(
    role: Role,
    options: { fleetOnly: boolean; fallbackToPhone: boolean },
  ): Promise<InternalRecipient[]> {
    const users = await this.prisma.user.findMany({
      where: {
        role,
        blocked: false,
      },
      select: {
        id: true,
        nombreCompleto: true,
        telefono: true,
        numeroFlota: true,
      },
      orderBy: {
        nombreCompleto: 'asc',
      },
    });

    return users
      .map((user) => {
        const numbers = new Set<string>();
        const fleet = (user.numeroFlota ?? '').trim();
        const phone = (user.telefono ?? '').trim();

        if (options.fleetOnly) {
          if (fleet) {
            numbers.add(fleet);
          } else if (options.fallbackToPhone && phone) {
            numbers.add(phone);
          }
        } else {
          if (fleet) numbers.add(fleet);
          if (phone) numbers.add(phone);
        }

        return {
          userId: user.id,
          name: user.nombreCompleto,
          numbers: [...numbers],
        };
      })
      .filter((user) => user.numbers.length > 0);
  }
}