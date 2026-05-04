import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { MarketingStoryStatus, Role } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { MarketingConfigService } from './marketing-config.service';
import { MarketingGenerationService } from './marketing-generation.service';

@Injectable()
export class MarketingAutomationScheduler {
  private readonly logger = new Logger(MarketingAutomationScheduler.name);
  private readonly rdTimeZone = 'America/Santo_Domingo';
  private isRunning = false;

  constructor(
    private readonly prisma: PrismaService,
    private readonly configService: MarketingConfigService,
    private readonly generationService: MarketingGenerationService,
  ) {}

  @Cron(CronExpression.EVERY_MINUTE, { timeZone: 'America/Santo_Domingo' })
  async runAutomation() {
    if (this.isRunning) {
      return;
    }

    this.isRunning = true;
    try {
      const companyId = this.resolveCompanyId();
      const config = await this.configService.getOrCreate(companyId);
      if (!config.active || config.paused) {
        return;
      }

      const now = new Date();
      const today = this.toRdDateOnly(now);
      const stories = await this.prisma.marketingDailyStory.findMany({
        where: {
          companyId,
          date: today,
        },
        orderBy: { createdAt: 'asc' },
      });

      if (stories.length === 0) {
        if (!this.canGenerateBySchedule(now, config.generationTime)) {
          return;
        }

        this.logger.log('Generando estados automaticamente...');
        const actorUserId = await this.resolveActorUserId();
        const generated = await this.generationService.generateMissingStories(companyId, today, actorUserId);
        await this.logActivity(companyId, 'AUTO_GENERATED', 'Generacion automatica de estados diarios', {
          date: this.toIsoDate(today),
          generatedCount: generated.length,
        }, actorUserId);
        return;
      }

      const pendingStories = stories.filter(
        (item) => item.status === MarketingStoryStatus.PENDING || item.status === MarketingStoryStatus.REGENERATED,
      );

      if (pendingStories.length === 0) {
        this.logger.log('Estados ya existen, no se genera');
        return;
      }

      if (!config.autoRegenerate) {
        this.logger.log('Estados ya existen, no se genera');
        return;
      }

      const shouldRegenerate = this.shouldRegenerate(now, pendingStories, config.regenerateAfterHours);
      if (!shouldRegenerate) {
        this.logger.log('Estados ya existen, no se genera');
        return;
      }

      this.logger.log('Regenerando estados por timeout');
      const actorUserId = await this.resolveActorUserId();
      await this.prisma.marketingDailyStory.deleteMany({
        where: {
          companyId,
          date: today,
          status: {
            in: [MarketingStoryStatus.PENDING, MarketingStoryStatus.REGENERATED],
          },
        },
      });

      const generated = await this.generationService.generateMissingStories(companyId, today, actorUserId);
      await this.logActivity(companyId, 'AUTO_REGENERATED', 'Regeneracion automatica por timeout de aprobacion', {
        date: this.toIsoDate(today),
        regenerateAfterHours: config.regenerateAfterHours,
        generatedCount: generated.length,
      }, actorUserId);
    } catch (error) {
      this.logger.error(
        'Error ejecutando automatizacion de Publicidad',
        error instanceof Error ? error.stack : String(error),
      );
    } finally {
      this.isRunning = false;
    }
  }

  private resolveCompanyId() {
    return process.env.COMPANY_ID ?? '00000000-0000-0000-0000-000000000001';
  }

  private async resolveActorUserId() {
    const envUserId = (process.env.MARKETING_AUTOMATION_USER_ID ?? '').trim();
    if (envUserId) {
      const user = await this.prisma.user.findUnique({
        where: { id: envUserId },
        select: { id: true },
      });
      if (user?.id) {
        return user.id;
      }
    }

    const admin = await this.prisma.user.findFirst({
      where: { role: Role.ADMIN },
      select: { id: true },
      orderBy: { createdAt: 'asc' },
    });
    return admin?.id ?? null;
  }

  private toRdDateOnly(now: Date) {
    const formatter = new Intl.DateTimeFormat('en-US', {
      timeZone: this.rdTimeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    });
    const parts = formatter.formatToParts(now);
    const year = Number(parts.find((item) => item.type === 'year')?.value ?? '1970');
    const month = Number(parts.find((item) => item.type === 'month')?.value ?? '01');
    const day = Number(parts.find((item) => item.type === 'day')?.value ?? '01');
    return new Date(Date.UTC(year, month - 1, day));
  }

  private canGenerateBySchedule(now: Date, generationTime: string) {
    const [configHours, configMinutes] = generationTime.split(':');
    const targetMinutes = (Number(configHours) || 0) * 60 + (Number(configMinutes) || 0);

    const formatter = new Intl.DateTimeFormat('en-US', {
      timeZone: this.rdTimeZone,
      hour: '2-digit',
      minute: '2-digit',
      hourCycle: 'h23',
    });
    const parts = formatter.formatToParts(now);
    const hours = Number(parts.find((item) => item.type === 'hour')?.value ?? '00');
    const minutes = Number(parts.find((item) => item.type === 'minute')?.value ?? '00');
    const currentMinutes = hours * 60 + minutes;
    return currentMinutes >= targetMinutes;
  }

  private shouldRegenerate(
    now: Date,
    pendingStories: Array<{ updatedAt: Date }>,
    regenerateAfterHours: number,
  ) {
    const latestPendingUpdate = pendingStories
      .map((item) => item.updatedAt.getTime())
      .reduce((max, value) => Math.max(max, value), 0);
    if (!latestPendingUpdate) {
      return false;
    }

    const elapsedMs = now.getTime() - latestPendingUpdate;
    return elapsedMs >= regenerateAfterHours * 60 * 60 * 1000;
  }

  private toIsoDate(value: Date) {
    const year = value.getUTCFullYear();
    const month = `${value.getUTCMonth() + 1}`.padStart(2, '0');
    const day = `${value.getUTCDate()}`.padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  private async logActivity(
    companyId: string,
    action: 'AUTO_GENERATED' | 'AUTO_REGENERATED',
    description: string,
    metadata: unknown,
    userId: string | null,
  ) {
    await this.prisma.marketingActivityLog.create({
      data: {
        companyId,
        action,
        description,
        userId,
        metadata: metadata as any,
      },
    });
  }
}