import { ConflictException, Injectable } from '@nestjs/common';
import { MarketingStoryStatus, MarketingStoryType } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { MarketingApprovalService } from './marketing-approval.service';
import { MarketingConfigService } from './marketing-config.service';
import { MarketingGenerationService } from './marketing-generation.service';
import { MarketingHistoryQueryDto } from './dto/marketing-query.dto';
import { UpdateMarketingConfigDto } from './dto/update-marketing-config.dto';
import { UpdateMarketingStoryDto } from './dto/update-marketing-story.dto';

@Injectable()
export class MarketingService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly generation: MarketingGenerationService,
    private readonly approvals: MarketingApprovalService,
    private readonly configService: MarketingConfigService,
  ) {}

  resolveCompanyId() {
    return process.env.COMPANY_ID ?? '00000000-0000-0000-0000-000000000001';
  }

  parseDateOnly(raw?: string): Date {
    const source = (raw ?? '').trim();
    if (!source) {
      const now = new Date();
      return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
    }
    const parsed = new Date(source);
    if (Number.isNaN(parsed.getTime())) {
      const now = new Date();
      return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
    }
    return new Date(Date.UTC(parsed.getUTCFullYear(), parsed.getUTCMonth(), parsed.getUTCDate()));
  }

  async getDashboard(companyId: string, date: Date) {
    const config = await this.configService.getOrCreate(companyId);
    const stories = await this.prisma.marketingDailyStory.findMany({
      where: {
        companyId,
        date,
      },
    });

    const pending = stories.filter(
      (item) => item.status === MarketingStoryStatus.PENDING || item.status === MarketingStoryStatus.REGENERATED,
    ).length;
    const approved = stories.filter((item) => item.status === MarketingStoryStatus.APPROVED).length;

    const lastGeneration = await this.prisma.marketingActivityLog.findFirst({
      where: {
        companyId,
        action: 'MARKETING_STORIES_GENERATED',
      },
      orderBy: { createdAt: 'desc' },
    });

    return {
      flowStatus: config.paused ? 'PAUSADO' : config.active ? 'ACTIVO' : 'INACTIVO',
      pendingApprovalCount: pending,
      approvedTodayCount: approved,
      lastGenerationAt: lastGeneration?.createdAt ?? null,
      nextSuggestedGeneration: this.nextGenerationSuggestion(config.generationTime),
      config,
    };
  }

  async listDailyStories(companyId: string, date: Date) {
    const stories = await this.prisma.marketingDailyStory.findMany({
      where: {
        companyId,
        date,
      },
      include: {
        approvedByUser: {
          select: {
            id: true,
            nombreCompleto: true,
          },
        },
      },
      orderBy: { type: 'asc' },
    });

    return {
      date,
      items: stories,
    };
  }

  async generateMissingStories(companyId: string, date: Date, userId: string) {
    const config = await this.configService.getOrCreate(companyId);
    if (config.paused) {
      throw new ConflictException('El flujo de Publicidad esta pausado. Activalo para generar contenido.');
    }
    return this.generation.generateMissingStories(companyId, date, userId);
  }

  async approveStory(companyId: string, storyId: string, userId: string) {
    return this.approvals.approve(companyId, storyId, userId);
  }

  async rejectStory(companyId: string, storyId: string, userId: string, reason?: string) {
    return this.approvals.reject(companyId, storyId, userId, reason);
  }

  async regenerateStory(companyId: string, storyId: string, userId: string) {
    return this.generation.regenerateStory(companyId, storyId, userId);
  }

  async editStory(companyId: string, storyId: string, dto: UpdateMarketingStoryDto, userId: string) {
    return this.approvals.edit(companyId, storyId, dto, userId);
  }

  async getHistory(companyId: string, query: MarketingHistoryQueryDto) {
    const page = Math.max(1, Number(query.page ?? 1));
    const limit = Math.min(100, Math.max(1, Number(query.limit ?? 20)));
    const skip = (page - 1) * limit;

    const fromDate = query.from ? this.parseDateOnly(query.from) : undefined;
    const toDate = query.to ? this.parseDateOnly(query.to) : undefined;
    const search = (query.search ?? '').trim();

    const where: any = {
      companyId,
      ...(query.type ? { type: query.type as MarketingStoryType } : {}),
      ...(query.status ? { status: query.status as MarketingStoryStatus } : {}),
      ...(fromDate || toDate
        ? {
            date: {
              ...(fromDate ? { gte: fromDate } : {}),
              ...(toDate ? { lte: toDate } : {}),
            },
          }
        : {}),
      ...(search
        ? {
            OR: [
              { title: { contains: search, mode: 'insensitive' } },
              { shortText: { contains: search, mode: 'insensitive' } },
            ],
          }
        : {}),
    };

    const [items, total] = await this.prisma.$transaction([
      this.prisma.marketingDailyStory.findMany({
        where,
        orderBy: [{ date: 'desc' }, { updatedAt: 'desc' }],
        skip,
        take: limit,
        include: {
          approvedByUser: {
            select: {
              id: true,
              nombreCompleto: true,
            },
          },
        },
      }),
      this.prisma.marketingDailyStory.count({ where }),
    ]);

    return {
      items,
      total,
      page,
      limit,
    };
  }

  async getConfig(companyId: string) {
    return this.configService.getOrCreate(companyId);
  }

  async updateConfig(companyId: string, dto: UpdateMarketingConfigDto, userId: string) {
    const updated = await this.configService.update(companyId, dto, userId);
    await this.log(companyId, 'MARKETING_CONFIG_UPDATED', 'Configuracion de marketing actualizada', userId, dto);
    return updated;
  }

  async activateFlow(companyId: string, userId: string) {
    const updated = await this.configService.activateFlow(companyId, userId);
    await this.log(companyId, 'MARKETING_FLOW_ACTIVATED', 'Flujo de marketing activado', userId, null);
    return updated;
  }

  async pauseFlow(companyId: string, userId: string) {
    const updated = await this.configService.pauseFlow(companyId, userId);
    await this.log(companyId, 'MARKETING_FLOW_PAUSED', 'Flujo de marketing pausado', userId, null);
    return updated;
  }

  async resetFlow(companyId: string, userId: string) {
    const updated = await this.configService.resetFlow(companyId, userId);
    await this.log(companyId, 'MARKETING_FLOW_RESET', 'Flujo de marketing reiniciado', userId, null);
    return updated;
  }

  private async log(
    companyId: string,
    action: string,
    description: string,
    userId: string,
    metadata: unknown,
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

  private nextGenerationSuggestion(generationTime: string) {
    const [hoursText, minutesText] = generationTime.split(':');
    const hours = Number(hoursText);
    const minutes = Number(minutesText);

    const now = new Date();
    const scheduled = new Date(now);
    scheduled.setHours(Number.isFinite(hours) ? hours : 8);
    scheduled.setMinutes(Number.isFinite(minutes) ? minutes : 0);
    scheduled.setSeconds(0, 0);

    if (scheduled <= now) {
      scheduled.setDate(scheduled.getDate() + 1);
    }
    return scheduled;
  }
}
