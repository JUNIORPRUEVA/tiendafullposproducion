import { Injectable, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { hostname } from 'os';
import { PrismaService } from '../prisma/prisma.service';
import { buildNotificationMessage } from './notification-templates';
import { EvolutionWhatsAppService } from './evolution-whatsapp.service';
import { NotificationPayload } from './notification.types';

const WORKER_ID = `${hostname()}-${process.pid}`;

@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly evolution: EvolutionWhatsAppService,
  ) {}

  private pad2(n: number) {
    return String(n).padStart(2, '0');
  }

  private pad3(n: number) {
    return String(n).padStart(3, '0');
  }

  private computeFallbackOrderNumber(params: { createdAt?: Date | null; serviceId: string }) {
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

  private extractServiceIdFromPayload(payload: unknown): string | null {
    try {
      const p: any = payload as any;
      const direct = p?.serviceId ? String(p.serviceId) : '';
      if (direct) return direct;
      const dataId = p?.data?.serviceId ? String(p.data.serviceId) : '';
      if (dataId) return dataId;
      return null;
    } catch {
      return null;
    }
  }

  private async resolveServiceOrderNumber(serviceId: string): Promise<string | null> {
    const id = (serviceId ?? '').toString().trim();
    if (!id) return null;

    try {
      const service = await this.prisma.service.findUnique({
        where: { id },
        select: { id: true, orderNumber: true, createdAt: true } as any,
      });

      if (!service) return null;
      const raw = typeof (service as any).orderNumber === 'string' ? (service as any).orderNumber.trim() : '';
      if (raw) return raw;

      const createdAt = (service as any).createdAt instanceof Date ? (service as any).createdAt : null;
      return this.computeFallbackOrderNumber({ createdAt, serviceId: id });
    } catch {
      // Best-effort: if migrations are missing, try again without selecting orderNumber.
      try {
        const service = await this.prisma.service.findUnique({
          where: { id },
          select: { id: true, createdAt: true } as any,
        });

        if (!service) return null;
        const createdAt = (service as any).createdAt instanceof Date ? (service as any).createdAt : null;
        return this.computeFallbackOrderNumber({ createdAt, serviceId: id });
      } catch {
        return null;
      }
    }
  }

  private stripServiceIdFromMessage(messageText: string, serviceId: string) {
    const id = (serviceId ?? '').toString().trim();
    if (!id) return messageText;
    return messageText
      .replace(`ID: ${id}.`, '')
      .replace(`ID: ${id}`, '')
      .replace(/\s{2,}/g, ' ')
      .trim();
  }

  private injectOrderNumberLine(messageText: string, orderNumber: string) {
    if (!orderNumber.trim()) return messageText;
    if (messageText.toLowerCase().includes('orden:')) return messageText;

    const orderLine = `Orden: ${orderNumber}`;
    if (messageText.includes('\n')) {
      const lines = messageText.split('\n');
      lines.splice(1, 0, orderLine);
      return lines.join('\n');
    }

    const base = messageText.trim();
    if (!base) return orderLine;
    const sep = base.endsWith('.') ? ' ' : '. ';
    return `${base}${sep}${orderLine}.`;
  }

  private async maybeInjectOrderNumber(messageText: string, payload?: unknown) {
    const serviceId = this.extractServiceIdFromPayload(payload);
    if (!serviceId) return messageText;

    const orderNumber = await this.resolveServiceOrderNumber(serviceId);
    if (!orderNumber) return messageText;

    const stripped = this.stripServiceIdFromMessage(messageText, serviceId);
    return this.injectOrderNumberLine(stripped, orderNumber);
  }

  private formatLocalYmdHm(d: Date) {
    const yyyy = d.getFullYear();
    const mm = this.pad2(d.getMonth() + 1);
    const dd = this.pad2(d.getDate());
    const hh = this.pad2(d.getHours());
    const min = this.pad2(d.getMinutes());
    return `${yyyy}-${mm}-${dd} ${hh}:${min}`;
  }

  private computeNextBusinessReminderAt(now: Date) {
    const next = new Date(now.getTime() + 60 * 60 * 1000);

    const startOfDay = new Date(next);
    startOfDay.setHours(9, 0, 0, 0);

    const endOfDay = new Date(next);
    endOfDay.setHours(18, 0, 0, 0);

    if (next < startOfDay) return startOfDay;
    if (next > endOfDay) {
      const tomorrow = new Date(next);
      tomorrow.setDate(tomorrow.getDate() + 1);
      tomorrow.setHours(9, 0, 0, 0);
      return tomorrow;
    }

    // If it's exactly within business hours (<= 18:00), keep it.
    return next;
  }

  private isReservationStillDue(service: {
    status: string;
    orderType: string;
    currentPhase: string;
    scheduledStart: Date | null;
  }) {
    const status = (service.status ?? '').toString();
    if (['CANCELLED', 'CLOSED', 'COMPLETED'].includes(status)) return false;

    const phase = (service.currentPhase ?? '').toString();
    const isReserva = phase === 'RESERVA';
    if (!isReserva) return false;

    if (!service.scheduledStart) return false;
    return service.scheduledStart.getTime() <= Date.now();
  }

  private buildReservationReminderMessage(params: {
    scheduledStart: Date;
    scheduledEnd: Date | null;
    serviceTitle: string;
    serviceDetail: string | null;
    customerName: string;
    customerPhoneRaw: string | null;
    sequence?: number | null;
  }) {
    const whenText = this.formatLocalYmdHm(params.scheduledStart);
    const customerPhone = (params.customerPhoneRaw ?? '').toString().trim();
    const customerDigits = this.evolution.normalizeWhatsAppNumber(customerPhone);

    const seq = typeof params.sequence === 'number' && Number.isFinite(params.sequence) && params.sequence > 0
      ? Math.floor(params.sequence)
      : null;

    const prefill = [
      `Hola ${params.customerName},`,
      `le escribo para confirmar su cita de ${params.serviceTitle}.`,
      `Fecha/hora: ${whenText}.`,
      '¿Le queda bien ese horario?',
      'Gracias.',
    ].join(' ');

    const waLink = customerDigits
      ? `https://wa.me/${customerDigits}?text=${encodeURIComponent(prefill)}`
      : '';

    const messageLines = [
      seq ? `*Recordatorio de reserva (#${seq})*` : '*Recordatorio de reserva*',
      `Servicio: ${params.serviceTitle}`,
      params.serviceDetail ? `Detalle: ${params.serviceDetail}` : null,
      `Cliente: ${params.customerName}`,
      customerPhone ? `Teléfono: ${customerPhone}` : 'Teléfono: (no registrado)',
      `Agenda: ${whenText}`,
      waLink ? `WhatsApp cliente: ${waLink}` : 'WhatsApp cliente: (teléfono inválido)',
      'Por favor confirmar con el cliente. Avisar en la app cualquier detalle.',
    ].filter(Boolean) as string[];

    return { messageText: messageLines.join('\n'), waLink: waLink || null, customerPhone: customerPhone || null };
  }

  async upsertWhatsAppRawTextScheduled(params: {
    dedupeKey: string;
    toNumber: string;
    messageText: string;
    nextAttemptAt: Date;
    payload?: unknown;
    recipientUserId?: string | null;
  }) {
    const dedupeKey = (params.dedupeKey ?? '').toString().trim();
    if (!dedupeKey) {
      throw new Error('dedupeKey es requerido');
    }

    const rawPhone = (params.toNumber ?? '').toString().trim();
    const normalized = this.evolution.normalizeWhatsAppNumber(rawPhone);
    let messageText = (params.messageText ?? '').toString();
    messageText = await this.maybeInjectOrderNumber(messageText, params.payload);

    const now = new Date();

    const commonData = {
      channel: 'WHATSAPP' as const,
      contentType: 'TEXT' as any,
      templateKey: 'custom_text',
      dedupeKey,
      messageText,
      mediaBase64: null as any,
      mediaFileName: null as any,
      mediaMimeType: null as any,
      payload: (params.payload ?? null) as any,
      recipientUserId: (params.recipientUserId ?? null) as any,
      toNumber: rawPhone,
      toNumberNormalized: normalized || '',
      lockedAt: null as any,
      lockedBy: null as any,
      lastStatusCode: null as any,
    };

    if (!normalized) {
      return this.prisma.notificationOutbox.upsert({
        where: { dedupeKey },
        create: {
          ...commonData,
          status: 'FAILED',
          attempts: 0,
          nextAttemptAt: now,
          lastError: 'Número de WhatsApp inválido',
          sentAt: null,
        },
        update: {
          ...commonData,
          status: 'FAILED',
          attempts: 0,
          nextAttemptAt: now,
          lastError: 'Número de WhatsApp inválido',
          sentAt: null,
        },
      });
    }

    if (!messageText.trim()) {
      return this.prisma.notificationOutbox.upsert({
        where: { dedupeKey },
        create: {
          ...commonData,
          status: 'FAILED',
          attempts: 0,
          nextAttemptAt: now,
          lastError: 'Mensaje vacío',
          sentAt: null,
        },
        update: {
          ...commonData,
          status: 'FAILED',
          attempts: 0,
          nextAttemptAt: now,
          lastError: 'Mensaje vacío',
          sentAt: null,
        },
      });
    }

    return this.prisma.notificationOutbox.upsert({
      where: { dedupeKey },
      create: {
        ...commonData,
        status: 'PENDING',
        attempts: 0,
        nextAttemptAt: params.nextAttemptAt,
        lastError: null,
        sentAt: null,
      },
      update: {
        ...commonData,
        status: 'PENDING',
        attempts: 0,
        nextAttemptAt: params.nextAttemptAt,
        lastError: null,
        sentAt: null,
      },
    });
  }

  async enqueueWhatsAppRawText(params: {
    toNumber: string;
    messageText: string;
    dedupeKey?: string;
    payload?: unknown;
  }) {
    const rawPhone = (params.toNumber ?? '').toString().trim();
    const normalized = this.evolution.normalizeWhatsAppNumber(rawPhone);
    let messageText = (params.messageText ?? '').toString();
    messageText = await this.maybeInjectOrderNumber(messageText, params.payload);

    if (!normalized) {
      return this.prisma.notificationOutbox.create({
        data: {
          channel: 'WHATSAPP',
          status: 'FAILED',
          templateKey: 'custom_text',
          dedupeKey: params.dedupeKey ?? null,
          messageText,
          payload: (params.payload ?? null) as any,
          recipientUserId: null,
          toNumber: rawPhone,
          toNumberNormalized: '',
          attempts: 0,
          nextAttemptAt: new Date(),
          lastError: 'Número de WhatsApp inválido',
        },
      });
    }

    if (!messageText.trim()) {
      return this.prisma.notificationOutbox.create({
        data: {
          channel: 'WHATSAPP',
          status: 'FAILED',
          templateKey: 'custom_text',
          dedupeKey: params.dedupeKey ?? null,
          messageText,
          payload: (params.payload ?? null) as any,
          recipientUserId: null,
          toNumber: rawPhone,
          toNumberNormalized: normalized,
          attempts: 0,
          nextAttemptAt: new Date(),
          lastError: 'Mensaje vacío',
        },
      });
    }

    return this.prisma.notificationOutbox.create({
      data: {
        channel: 'WHATSAPP',
        contentType: 'TEXT' as any,
        status: 'PENDING',
        templateKey: 'custom_text',
        dedupeKey: params.dedupeKey ?? null,
        messageText,
        payload: (params.payload ?? null) as any,
        recipientUserId: null,
        toNumber: rawPhone,
        toNumberNormalized: normalized,
        attempts: 0,
        nextAttemptAt: new Date(),
      },
    });
  }

  async enqueueWhatsAppDocument(params: {
    toNumber: string;
    messageText: string;
    fileName: string;
    bytes: Uint8Array;
    mimeType?: string;
    dedupeKey?: string;
    payload?: unknown;
    recipientUserId?: string | null;
  }) {
    const rawPhone = (params.toNumber ?? '').toString().trim();
    const normalized = this.evolution.normalizeWhatsAppNumber(rawPhone);
    const fileName = (params.fileName ?? '').toString().trim() || 'document.pdf';
    const mimeType = (params.mimeType ?? 'application/pdf').toString().trim() || 'application/pdf';
    const bytes = params.bytes instanceof Uint8Array ? params.bytes : new Uint8Array(params.bytes);
    let messageText = (params.messageText ?? '').toString();
    messageText = await this.maybeInjectOrderNumber(messageText, params.payload);

    const data = {
      channel: 'WHATSAPP' as const,
      contentType: 'DOCUMENT' as any,
      status: (!normalized || !bytes.length || !messageText.trim()) ? 'FAILED' as const : 'PENDING' as const,
      templateKey: 'custom_document',
      dedupeKey: params.dedupeKey ?? null,
      messageText,
      mediaBase64: bytes.length ? Buffer.from(bytes).toString('base64') : null,
      mediaFileName: fileName,
      mediaMimeType: mimeType,
      payload: (params.payload ?? null) as any,
      recipientUserId: (params.recipientUserId ?? null) as any,
      toNumber: rawPhone,
      toNumberNormalized: normalized || '',
      attempts: 0,
      nextAttemptAt: new Date(),
      lastError: !normalized
        ? 'Número de WhatsApp inválido'
        : !bytes.length
          ? 'El documento está vacío'
          : !messageText.trim()
            ? 'Mensaje vacío'
            : null,
    };

    if (params.dedupeKey?.trim()) {
      return this.prisma.notificationOutbox.upsert({
        where: { dedupeKey: params.dedupeKey.trim() },
        create: data,
        update: {
          ...data,
          lockedAt: null,
          lockedBy: null,
          sentAt: null,
          lastStatusCode: null,
        },
      });
    }

    return this.prisma.notificationOutbox.create({
      data,
    });
  }

  async enqueueWhatsAppToUser(params: {
    recipientUserId: string;
    payload: NotificationPayload;
    dedupeKey?: string;
  }) {
    const user = await this.prisma.user.findUnique({
      where: { id: params.recipientUserId },
      select: { id: true, telefono: true, blocked: true },
    });

    const rawPhone = (user?.telefono ?? '').trim();
    const normalized = this.evolution.normalizeWhatsAppNumber(rawPhone);

    let messageText = buildNotificationMessage(params.payload);
    messageText = await this.maybeInjectOrderNumber(messageText, params.payload);

    if (!user || user.blocked) {
      return this.prisma.notificationOutbox.create({
        data: {
          channel: 'WHATSAPP',
          contentType: 'TEXT' as any,
          status: 'FAILED',
          templateKey: params.payload.template,
          dedupeKey: params.dedupeKey ?? null,
          messageText,
          payload: params.payload as unknown as Prisma.InputJsonValue,
          recipientUserId: params.recipientUserId,
          toNumber: rawPhone,
          toNumberNormalized: normalized,
          attempts: 0,
          nextAttemptAt: new Date(),
          lastError: 'Usuario inválido o bloqueado',
        },
      });
    }

    if (!normalized) {
      return this.prisma.notificationOutbox.create({
        data: {
          channel: 'WHATSAPP',
          contentType: 'TEXT' as any,
          status: 'FAILED',
          templateKey: params.payload.template,
          dedupeKey: params.dedupeKey ?? null,
          messageText,
          payload: params.payload as unknown as Prisma.InputJsonValue,
          recipientUserId: params.recipientUserId,
          toNumber: rawPhone,
          toNumberNormalized: '',
          attempts: 0,
          nextAttemptAt: new Date(),
          lastError: 'Usuario no tiene teléfono válido',
        },
      });
    }

    return this.prisma.notificationOutbox.create({
      data: {
        channel: 'WHATSAPP',
        contentType: 'TEXT' as any,
        status: 'PENDING',
        templateKey: params.payload.template,
        dedupeKey: params.dedupeKey ?? null,
        messageText,
        payload: params.payload as unknown as Prisma.InputJsonValue,
        recipientUserId: params.recipientUserId,
        toNumber: rawPhone,
        toNumberNormalized: normalized,
        attempts: 0,
        nextAttemptAt: new Date(),
      },
    });
  }

  private backoffMs(attempts: number) {
    // attempts is 1-based after a failure.
    if (attempts <= 1) return 60_000;
    if (attempts === 2) return 5 * 60_000;
    if (attempts === 3) return 15 * 60_000;
    if (attempts === 4) return 60 * 60_000;
    return 3 * 60 * 60_000;
  }

  async processOutboxBatch(limit = 25) {
    const now = new Date();
    const lockExpiry = new Date(now.getTime() - 2 * 60_000);

    const claimed = await this.prisma.$transaction(async (tx) => {
      const rows = await tx.notificationOutbox.findMany({
        where: {
          status: { in: ['PENDING', 'SENDING'] },
          nextAttemptAt: { lte: now },
          OR: [{ lockedAt: null }, { lockedAt: { lt: lockExpiry } }],
        },
        orderBy: [{ nextAttemptAt: 'asc' }, { createdAt: 'asc' }],
        take: limit,
      });

      if (!rows.length) return [];

      await tx.notificationOutbox.updateMany({
        where: { id: { in: rows.map((r) => r.id) } },
        data: {
          status: 'SENDING',
          lockedAt: now,
          lockedBy: WORKER_ID,
        },
      });

      return rows;
    });

    for (const row of claimed) {
      try {
        // Reservation reminders: enforce "still RESERVA and already due" before sending,
        // and restrict sending to business hours (09:00-18:00).
        try {
          const payload = (row.payload ?? null) as any;
          const kind = payload?.kind ? String(payload.kind) : '';
          const serviceId = payload?.serviceId ? String(payload.serviceId) : '';
          const cadence = payload?.cadence ? String(payload.cadence) : '';

          if (kind === 'reservation_reminder' && serviceId) {
            const service = await this.prisma.service.findUnique({
              where: { id: serviceId },
              select: {
                id: true,
                isDeleted: true,
                status: true,
                orderType: true,
                currentPhase: true,
                scheduledStart: true,
              },
            });

            if (!service || service.isDeleted || !this.isReservationStillDue(service as any)) {
              await this.prisma.notificationOutbox.update({
                where: { id: row.id },
                data: {
                  status: 'FAILED',
                  lockedAt: null,
                  lockedBy: null,
                  lastError: 'Recordatorio detenido: la orden ya no está en RESERVA o fue reagendada',
                  lastStatusCode: null,
                },
              });
              continue;
            }

            // Business-hours restriction is for hourly follow-ups.
            if (cadence === 'hourly_business_hours') {
              const t = new Date();
              const hh = t.getHours();
              const mm = t.getMinutes();
              const ss = t.getSeconds();

              const isAfter18 = hh > 18 || (hh === 18 && (mm > 0 || ss > 0));
              const isBefore9 = hh < 9;
              if (isBefore9 || isAfter18) {
                const next = new Date(t);
                if (isBefore9) {
                  next.setHours(9, 0, 0, 0);
                } else {
                  next.setDate(next.getDate() + 1);
                  next.setHours(9, 0, 0, 0);
                }

                await this.prisma.notificationOutbox.update({
                  where: { id: row.id },
                  data: {
                    status: 'PENDING',
                    nextAttemptAt: next,
                    lockedAt: null,
                    lockedBy: null,
                    lastError: null,
                    lastStatusCode: null,
                  },
                });
                continue;
              }
            }
          }
        } catch {
          // ignore and attempt send
        }

        const contentType = String((row as any).contentType ?? 'TEXT').toUpperCase();
        if (contentType === 'DOCUMENT') {
          const mediaBase64 = ((row as any).mediaBase64 ?? '').toString();
          const mediaFileName = ((row as any).mediaFileName ?? '').toString().trim() || 'document.pdf';
          if (!mediaBase64.trim()) {
            throw new Error('Documento faltante en notification_outbox');
          }

          await this.evolution.sendPdfDocument({
            toNumber: row.toNumberNormalized,
            bytes: Buffer.from(mediaBase64, 'base64'),
            fileName: mediaFileName,
            caption: row.messageText,
          });
        } else {
          await this.evolution.sendTextMessage({
            toNumber: row.toNumberNormalized,
            message: row.messageText,
          });
        }

        this.logger.log(`notification sent id=${row.id} contentType=${contentType} to=${row.toNumberNormalized}`);

        await this.prisma.notificationOutbox.update({
          where: { id: row.id },
          data: {
            status: 'SENT',
            sentAt: new Date(),
            lockedAt: null,
            lockedBy: null,
            lastError: null,
            lastStatusCode: null,
          },
        });

        // If this was a reservation reminder, chain the next hourly reminder (business hours only)
        // while the service remains due and in RESERVA.
        try {
          const payload = (row.payload ?? null) as any;
          const kind = payload?.kind ? String(payload.kind) : '';
          const serviceId = payload?.serviceId ? String(payload.serviceId) : '';

          if (kind === 'reservation_reminder' && serviceId) {
            const service = await this.prisma.service.findUnique({
              where: { id: serviceId },
              select: {
                id: true,
                isDeleted: true,
                status: true,
                orderType: true,
                currentPhase: true,
                scheduledStart: true,
                scheduledEnd: true,
                title: true,
                description: true,
                createdByUserId: true,
                customer: { select: { nombre: true, telefono: true } },
              },
            });

            if (service && !service.isDeleted && this.isReservationStillDue(service as any)) {
              const creator = await this.prisma.user.findUnique({
                where: { id: service.createdByUserId },
                select: { id: true, blocked: true, numeroFlota: true },
              });

              const fleetNumber = (creator?.numeroFlota ?? '').toString().trim();
              if (creator && !creator.blocked && fleetNumber && service.scheduledStart) {
                const nextAttemptAt = this.computeNextBusinessReminderAt(new Date());

                const prevSeqRaw = payload?.sequence;
                const prevSeq = typeof prevSeqRaw === 'number' && Number.isFinite(prevSeqRaw) && prevSeqRaw > 0
                  ? Math.floor(prevSeqRaw)
                  : 1;
                const nextSeq = prevSeq + 1;

                const customerName = (service.customer?.nombre ?? 'Cliente').toString().trim() || 'Cliente';
                const customerPhoneRaw = (service.customer?.telefono ?? '').toString().trim() || null;
                const serviceTitle = (service.title ?? '').toString().trim() || 'Reserva';
                const serviceDetail = (service.description ?? '').toString().trim() || null;

                const built = this.buildReservationReminderMessage({
                  scheduledStart: service.scheduledStart,
                  scheduledEnd: service.scheduledEnd,
                  serviceTitle,
                  serviceDetail,
                  customerName,
                  customerPhoneRaw,
                  sequence: nextSeq,
                });

                const minuteKey = nextAttemptAt.toISOString().slice(0, 16);
                await this.upsertWhatsAppRawTextScheduled({
                  dedupeKey: `reservation_reminder_hourly:${service.id}:${minuteKey}`,
                  toNumber: fleetNumber,
                  messageText: built.messageText,
                  nextAttemptAt,
                  recipientUserId: creator.id,
                  payload: {
                    kind: 'reservation_reminder',
                    serviceId: service.id,
                    cadence: 'hourly_business_hours',
                    sequence: nextSeq,
                    scheduledStart: service.scheduledStart.toISOString(),
                    scheduledEnd: service.scheduledEnd ? service.scheduledEnd.toISOString() : null,
                    customerName,
                    customerPhone: built.customerPhone,
                    customerWaMe: built.waLink,
                    nextAttemptAt: nextAttemptAt.toISOString(),
                  },
                });
              }
            }
          }
        } catch {
          // ignore
        }
      } catch (e) {
        const attempts = (row.attempts ?? 0) + 1;
        const maxAttempts = 6;
        const errMsg = (e as any)?.message ? String((e as any).message) : String(e);
        const statusCode = typeof (e as any)?.status === 'number' ? (e as any).status : null;

        this.logger.warn(`notification failed id=${row.id} attempts=${attempts} status=${statusCode ?? 'n/a'} error=${errMsg}`);

        await this.prisma.notificationOutbox.update({
          where: { id: row.id },
          data: {
            status: attempts >= maxAttempts ? 'FAILED' : 'PENDING',
            attempts,
            nextAttemptAt: new Date(Date.now() + this.backoffMs(attempts)),
            lockedAt: null,
            lockedBy: null,
            lastError: errMsg.slice(0, 1800),
            lastStatusCode: statusCode,
          },
        });
      }
    }
  }
}
