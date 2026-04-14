import { Injectable, Logger } from '@nestjs/common';
import { hostname } from 'os';
import { PrismaService } from '../prisma/prisma.service';
import {
  alignToNotificationBusinessHours,
  isWithinNotificationBusinessHours,
} from './notification-business-hours.util';
import { ServiceOrderNotificationsListener } from './service-order-notifications.listener';

const JOB_WORKER_ID = `${hostname()}-${process.pid}`;

@Injectable()
export class ServiceOrderNotificationJobsProcessor {
  private readonly logger = new Logger(ServiceOrderNotificationJobsProcessor.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly listener: ServiceOrderNotificationsListener,
  ) {}

  private backoffMs(attempts: number) {
    if (attempts <= 1) return 60_000;
    if (attempts === 2) return 5 * 60_000;
    if (attempts === 3) return 15 * 60_000;
    if (attempts === 4) return 60 * 60_000;
    return 3 * 60 * 60_000;
  }

  async processDueJobsBatch(limit = 10) {
    const now = new Date();
    const lockExpiry = new Date(now.getTime() - 2 * 60_000);

    const claimed = await this.prisma.$transaction(async (tx) => {
      const rows = await tx.serviceOrderNotificationJob.findMany({
        where: {
          status: { in: ['PENDING', 'PROCESSING'] },
          runAt: { lte: now },
          OR: [{ lockedAt: null }, { lockedAt: { lt: lockExpiry } }],
        },
        orderBy: [{ runAt: 'asc' }, { createdAt: 'asc' }],
        take: limit,
      });

      if (!rows.length) return [];

      await tx.serviceOrderNotificationJob.updateMany({
        where: { id: { in: rows.map((row) => row.id) } },
        data: {
          status: 'PROCESSING',
          lockedAt: now,
          lockedBy: JOB_WORKER_ID,
        },
      });

      return rows;
    });

    for (const row of claimed) {
      try {
        if (!isWithinNotificationBusinessHours()) {
          await this.prisma.serviceOrderNotificationJob.update({
            where: { id: row.id },
            data: {
              status: 'PENDING',
              runAt: alignToNotificationBusinessHours(new Date()),
              lockedAt: null,
              lockedBy: null,
              lastError: null,
            },
          });
          continue;
        }

        if (row.kind === 'THIRTY_MINUTES_BEFORE') {
          await this.listener.dispatchThirtyMinuteReminder(row.id);
        } else if (row.kind === 'FIFTEEN_MINUTES_PENDING') {
          await this.listener.dispatchPendingTechnicianReminder(row.id);
        }

        await this.prisma.serviceOrderNotificationJob.updateMany({
          where: { id: row.id, status: 'PROCESSING' },
          data: {
            status: 'COMPLETED',
            completedAt: new Date(),
            lockedAt: null,
            lockedBy: null,
            lastError: null,
          },
        });
      } catch (error) {
        const attempts = (row.attempts ?? 0) + 1;
        const message = error instanceof Error ? error.message : String(error);
        const maxAttempts = 6;

        this.logger.warn(`service-order notification job failed id=${row.id} attempts=${attempts} error=${message}`);

        await this.prisma.serviceOrderNotificationJob.update({
          where: { id: row.id },
          data: {
            status: attempts >= maxAttempts ? 'FAILED' : 'PENDING',
            attempts,
            runAt: new Date(Date.now() + this.backoffMs(attempts)),
            lockedAt: null,
            lockedBy: null,
            lastError: message.slice(0, 1800),
          },
        });
      }
    }
  }
}