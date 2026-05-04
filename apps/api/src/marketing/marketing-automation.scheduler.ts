import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { MarketingStoryStatus, Role } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { MarketingConfigService } from './marketing-config.service';
import { MarketingGenerationService } from './marketing-generation.service';
import { MarketingResearchService } from './marketing-research.service';

@Injectable()
export class MarketingAutomationScheduler {
  private readonly logger = new Logger(MarketingAutomationScheduler.name);
  private readonly rdTimeZone = 'America/Santo_Domingo';
  private isRunning = false;

  constructor(
    private readonly prisma: PrismaService,
    private readonly configService: MarketingConfigService,
    private readonly generationService: MarketingGenerationService,
    private readonly researchService: MarketingResearchService,
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
        const researchId = await this.ensureResearch(companyId, actorUserId);
        const generated = await this.generationService.generateMissingStories(companyId, today, actorUserId, researchId);
        await this.logActivity(companyId, 'AUTO_GENERATED', 'Generacion automatica de estados diarios', {
          date: this.toIsoDate(today),
          generatedCount: generated.length,
          researchId: researchId ?? null,
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

      const researchId2 = await this.ensureResearch(companyId, actorUserId);
      const generated = await this.generationService.generateMissingStories(companyId, today, actorUserId, researchId2);
      await this.logActivity(companyId, 'AUTO_REGENERATED', 'Regeneracion automatica por timeout de aprobacion', {
        date: this.toIsoDate(today),
        regenerateAfterHours: config.regenerateAfterHours,
        generatedCount: generated.length,
        researchId: researchId2 ?? null,
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

  private async ensureResearch(companyId: string, actorUserId: string | null): Promise<string | null> {
    try {
      const existing = await this.researchService.getUsableResearch(companyId);
      if (existing) {
        this.logger.log(`Investigacion existente reutilizada: ${existing.id}`);
        await this.logActivity(companyId, 'AUTO_RESEARCH_REUSED', 'Investigacion existente reutilizada para generacion de estados', {
          researchId: existing.id,
          status: existing.status,
        }, actorUserId).catch(() => {});
        return existing.id;
      }

      this.logger.log('Generando investigacion de mercado automatica...');
      const research = await this.researchService.generate(companyId, {}, actorUserId ?? '', false);
      await this.logActivity(companyId, 'AUTO_RESEARCH_GENERATED', 'Investigacion de mercado generada automaticamente', {
        researchId: research.id,
        confidenceScore: research.confidenceScore,
      }, actorUserId).catch(() => {});
      return research.id;
    } catch (error) {
      this.logger.error('Error en investigacion automatica', error instanceof Error ? error.stack : String(error));
      await this.logActivity(companyId, 'AUTO_RESEARCH_FAILED', 'Error al generar investigacion automatica de mercado', {
        error: error instanceof Error ? error.message : String(error),
      }, actorUserId).catch(() => {});
      return null;
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
    action: string,
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