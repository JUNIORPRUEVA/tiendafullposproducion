import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { hostname } from 'os';
import { PrismaService } from '../prisma/prisma.service';
import { buildNotificationMessage } from './notification-templates';
import { EvolutionWhatsAppService } from './evolution-whatsapp.service';
import { NotificationPayload } from './notification.types';

const WORKER_ID = `${hostname()}-${process.pid}`;

@Injectable()
export class NotificationsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly evolution: EvolutionWhatsAppService,
  ) {}

  async enqueueWhatsAppRawText(params: {
    toNumber: string;
    messageText: string;
    dedupeKey?: string;
    payload?: unknown;
  }) {
    const rawPhone = (params.toNumber ?? '').toString().trim();
    const normalized = this.evolution.normalizeWhatsAppNumber(rawPhone);
    const messageText = (params.messageText ?? '').toString();

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

    const messageText = buildNotificationMessage(params.payload);

    if (!user || user.blocked) {
      return this.prisma.notificationOutbox.create({
        data: {
          channel: 'WHATSAPP',
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
        await this.evolution.sendTextMessage({
          toNumber: row.toNumberNormalized,
          message: row.messageText,
        });

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
      } catch (e) {
        const attempts = (row.attempts ?? 0) + 1;
        const maxAttempts = 6;
        const errMsg = (e as any)?.message ? String((e as any).message) : String(e);
        const statusCode = typeof (e as any)?.status === 'number' ? (e as any).status : null;

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
