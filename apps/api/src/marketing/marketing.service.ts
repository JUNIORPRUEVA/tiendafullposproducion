import { ConflictException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { MarketingStoryStatus, MarketingStoryType } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { MarketingApprovalService } from './marketing-approval.service';
import { MarketingConfigService } from './marketing-config.service';
import { MarketingGenerationService } from './marketing-generation.service';
import { MarketingImageGenerationService } from './marketing-image-generation.service';
import { MarketingImageJobService } from './marketing-image-job.service';
import { MarketingMediaAssetService } from './marketing-media-asset.service';
import { MarketingResearchService } from './marketing-research.service';
import { MarketingStorageService } from './marketing-storage.service';
import { CreateMarketingMediaAssetDto, MarketingMediaAssetQueryDto, UpdateMarketingMediaAssetDto } from './dto/marketing-media-asset.dto';
import { MarketingHistoryQueryDto } from './dto/marketing-query.dto';
import { MarketingResetCleanDto } from './dto/marketing-reset-clean.dto';
import { UpdateMarketingConfigDto } from './dto/update-marketing-config.dto';
import { UpdateMarketingStoryDto } from './dto/update-marketing-story.dto';

@Injectable()
export class MarketingService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly generation: MarketingGenerationService,
    private readonly imageGeneration: MarketingImageGenerationService,
    private readonly imageJobs: MarketingImageJobService,
    private readonly approvals: MarketingApprovalService,
    private readonly configService: MarketingConfigService,
    private readonly researchService: MarketingResearchService,
    private readonly mediaAssets: MarketingMediaAssetService,
    private readonly marketingStorage: MarketingStorageService,
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
    const dailyRows = await this.prisma.marketingDailyStory.findMany({
      where: { companyId, date },
      orderBy: [{ updatedAt: 'desc' }, { createdAt: 'desc' }],
    });
    const stories = this.pickLatestStoryPerType(dailyRows);

    const pending = stories.filter(
      (item) => item.status === MarketingStoryStatus.PENDING || item.status === MarketingStoryStatus.REGENERATED,
    ).length;
    const approved = stories.filter((item) => item.status === MarketingStoryStatus.APPROVED).length;

    const lastGeneration = await this.prisma.marketingActivityLog.findFirst({
      where: { companyId, action: 'MARKETING_STORIES_GENERATED' },
      orderBy: { createdAt: 'desc' },
    });

    // Research data for dashboard
    const [latestResearch, researchConfig] = await Promise.all([
      this.researchService.getLatestResearch(companyId).catch(() => null),
      this.researchService.getOrCreateConfig(companyId).catch(() => null),
    ]);

    const now = new Date();
    let researchUsable = false;
    let nextAutoResearch: Date | null = null;
    let storiesFromCurrentResearch = 0;

    if (researchConfig) {
      const frequencyMs = researchConfig.researchFrequencyDays * 24 * 60 * 60 * 1000;
      if (latestResearch) {
        const age = now.getTime() - latestResearch.createdAt.getTime();
        researchUsable = (latestResearch.status === 'APPROVED' || latestResearch.status === 'DRAFT') && age <= frequencyMs;
        nextAutoResearch = new Date(latestResearch.createdAt.getTime() + frequencyMs);
        storiesFromCurrentResearch = stories.filter((s) => (s as any).researchId === latestResearch.id).length;
      } else {
        nextAutoResearch = new Date(now);
      }
    }

    return {
      flowStatus: config.paused ? 'PAUSADO' : config.active ? 'ACTIVO' : 'INACTIVO',
      pendingApprovalCount: pending,
      approvedTodayCount: approved,
      lastGenerationAt: lastGeneration?.createdAt ?? null,
      nextSuggestedGeneration: this.nextGenerationSuggestion(config.generationTime),
      config,
      // Research summary for dashboard
      latestResearch: latestResearch
        ? {
            id: latestResearch.id,
            status: latestResearch.status,
            date: latestResearch.date,
            confidenceScore: latestResearch.confidenceScore,
            dataSources: latestResearch.dataSources,
            createdAt: latestResearch.createdAt,
          }
        : null,
      researchUsable,
      nextAutoResearch,
      researchFrequencyDays: researchConfig?.researchFrequencyDays ?? 7,
      serviceRadiusKm: researchConfig?.serviceRadiusKm ?? 25,
      serviceZone: researchConfig ? `${researchConfig.city}, ${researchConfig.province}` : 'Higüey, La Altagracia',
      storiesFromCurrentResearch,
    };
  }

  async listDailyStories(companyId: string, date: Date) {
    const rows = await this.prisma.marketingDailyStory.findMany({
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
        research: {
          select: {
            id: true,
            status: true,
            confidenceScore: true,
          },
        },
        mediaAsset: true,
      },
      orderBy: [{ updatedAt: 'desc' }, { createdAt: 'desc' }],
    });
    const stories = this.pickLatestStoryPerType(rows);

    return {
      date,
      items: await Promise.all(stories.map((item) => this.normalizeStoryUrlsAsync(item))),
    };
  }

  async generateMissingStories(companyId: string, date: Date, userId: string, dto?: { selected_media_asset_ids?: string[] }) {
    const config = await this.configService.getOrCreate(companyId);
    if (config.paused) {
      throw new ConflictException('El flujo de Publicidad esta pausado. Activalo para generar contenido.');
    }

    let researchId: string | null = null;
    const usable = await this.researchService.getUsableResearch(companyId);
    if (usable) {
      researchId = usable.id;
    } else {
      const generated = await this.researchService.generate(companyId, {}, userId, false);
      if (generated.status !== 'APPROVED') {
        await this.researchService.approve(companyId, generated.id, userId);
      }
      researchId = generated.id;
    }

    const stories = await this.generation.generateMissingStories(
      companyId,
      date,
      userId,
      researchId,
      dto?.selected_media_asset_ids ?? [],
    );

    return {
      date: this.toDateOnly(date),
      message: 'Estados generados con imagen sugerida. Confirma o cambia la imagen antes de generar diseño.',
      queuedCount: 0,
      items: await Promise.all(stories.map((story) => this.normalizeStoryUrlsAsync(story))),
    };
  }

  async repairIncompleteStories(companyId: string, date: Date, userId: string) {
    const rows = await this.prisma.marketingDailyStory.findMany({
      where: {
        companyId,
        date,
      },
      orderBy: [{ updatedAt: 'desc' }, { createdAt: 'desc' }],
    });
    const latest = this.pickLatestStoryPerType(rows);

    const targeted = latest.filter((story) => this.getStoryMissingFields(story).length > 0);
    const repairedIds: string[] = [];
    const failed: Array<{ storyId: string; reason: string }> = [];

    for (const story of targeted) {
      const missing = this.getStoryMissingFields(story);
      try {
        if (missing.includes('prompt') || missing.includes('copy')) {
          await this.generation.regenerateStory(companyId, story.id, userId);
          this.imageJobs.enqueueStoryImageGeneration(story.id, companyId, userId);
        } else {
          await this.generation.queueStoryImageGeneration(
            companyId,
            story.id,
            userId,
            'Reparacion automatica de imagen',
          );
          this.imageJobs.enqueueStoryImageGeneration(
            story.id,
            companyId,
            userId,
            'Reparacion automatica de imagen',
          );
        }
        repairedIds.push(story.id);
      } catch (error) {
        const reason = error instanceof Error ? error.message : 'Error desconocido';
        failed.push({ storyId: story.id, reason });
      }
    }

    await this.log(
      companyId,
      'MARKETING_STORIES_REPAIR_INCOMPLETE',
      `Barrido de reparacion ejecutado (${repairedIds.length}/${targeted.length})`,
      userId,
      {
        date: this.toDateOnly(date),
        targeted: targeted.length,
        repaired: repairedIds.length,
        failed,
      },
    );

    return {
      date: this.toDateOnly(date),
      targeted: targeted.length,
      repaired: repairedIds.length,
      failed,
    };
  }

  async approveStory(companyId: string, storyId: string, userId: string) {
    return this.approvals.approve(companyId, storyId, userId);
  }

  async rejectStory(companyId: string, storyId: string, userId: string, reason?: string) {
    return this.approvals.reject(companyId, storyId, userId, reason);
  }

  async regenerateStory(companyId: string, storyId: string, userId: string) {
    const updated = await this.generation.regenerateStory(companyId, storyId, userId);
    return {
      message: 'Contenido regenerado con nueva imagen sugerida. Debes confirmar imagen para generar diseño.',
      item: await this.normalizeStoryUrlsAsync(updated),
    };
  }

  async regenerateStoryImage(companyId: string, storyId: string, userId: string, customPrompt?: string, sync = false) {
    if (sync) {
      const updated = await this.generation.regenerateStoryImageDirect(companyId, storyId, userId, customPrompt);
      return {
        message: 'Imagen generada en modo directo',
        item: await this.normalizeStoryUrlsAsync(updated),
      };
    }

    const updated = await this.generation.queueStoryImageGeneration(companyId, storyId, userId, customPrompt);
    this.imageJobs.enqueueStoryImageGeneration(updated.id, companyId, userId, customPrompt);
    return {
      message: 'Diseño en proceso',
      item: await this.normalizeStoryUrlsAsync(updated),
    };
  }

  async confirmStoryBaseImage(companyId: string, storyId: string, userId: string) {
    const updated = await this.generation.confirmBaseImageSelection(companyId, storyId, userId);
    return {
      message: 'Imagen base confirmada. Ya puedes generar el diseño.',
      item: await this.normalizeStoryUrlsAsync(updated),
    };
  }

  async generateStoryDesign(companyId: string, storyId: string, userId: string, customPrompt?: string) {
    return this.regenerateStoryImage(companyId, storyId, userId, customPrompt, false);
  }

  async getDebugVersion(companyId: string) {
    const providerConfigured = await this.imageGeneration.isProviderConfigured();
    const storage = this.marketingStorage.getDebugStorageConfig();
    const currentApiBase = (
      this.config.get<string>('API_BASE_URL') ??
      process.env.API_BASE_URL ??
      ''
    ).trim();

    return {
      buildTime: new Date().toISOString(),
      asyncImageJobsEnabled: true,
      providerConfigured,
      storageConfigured: storage.storageConfigured,
      publicBaseUrl: storage.publicBaseUrl,
      currentApiBase,
      uploadDir: storage.uploadDir,
      r2EndpointConfigured: storage.r2EndpointConfigured,
      r2BucketConfigured: storage.r2BucketConfigured,
      companyId,
      pid: process.pid,
    };
  }

  async debugTestImage(companyId: string, prompt: string) {
    const safePrompt = prompt.trim() || 'Genera una historia 9:16 de anuncio premium para seguridad electrónica en tienda.';
    const providerConfigured = await this.imageGeneration.isProviderConfigured();
    if (!providerConfigured) {
      throw new ConflictException('falta OPENAI_API_KEY (env o app_config.openAiApiKey)');
    }

    const storage = this.marketingStorage.getDebugStorageConfig();
    if (!storage.storageConfigured) {
      throw new ConflictException('storage no configurado: faltan variables R2');
    }

    const generated = await this.imageGeneration.generateOrPrepare({
      companyName: 'FULLTECH SRL',
      city: 'Higüey',
      country: 'República Dominicana',
      brandTone: 'tecnológico, limpio y profesional',
      brandColors: ['#0B1F3B', '#12C7D9', '#FFFFFF'],
      title: 'Prueba técnica de generación',
      cta: 'Contáctanos por WhatsApp',
      offer: safePrompt,
      visualConcept: 'Prueba técnica para validar generación real de imagen',
      designNotes: 'Formato 9:16, calidad comercial premium, sin texto sobreimpreso',
      baseImageUrl: '',
      imageCategory: 'Diagnóstico',
      serviceOrProduct: 'Publicidad',
      usedResearchAngle: 'Diagnóstico técnico',
    });

    const saved = await this.marketingStorage.saveGeneratedImage({
      companyId,
      storyType: 'debug',
      sourceUrl: generated.generatedImageUrl ?? '',
    });

    const publicUrl = `${saved.url ?? ''}`.trim();
    if (!publicUrl) {
      throw new ConflictException('error de storage: no se pudo obtener URL pública');
    }

    return {
      ok: true,
      provider: generated.generatedImageProvider,
      prompt: generated.prompt,
      generatedImageUrl: publicUrl,
      publicBaseUrl: storage.publicBaseUrl,
      metadata: generated.metadata,
    };
  }

  async changeStoryBaseImage(companyId: string, storyId: string, mediaAssetId: string, userId: string) {
    return this.generation.changeBaseImage(companyId, storyId, mediaAssetId, userId);
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
          research: {
            select: {
              id: true,
              status: true,
              confidenceScore: true,
            },
          },
          mediaAsset: true,
        },
      }),
      this.prisma.marketingDailyStory.count({ where }),
    ]);

    return {
      items: await Promise.all(items.map((item) => this.normalizeStoryUrlsAsync(item))),
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

  async listMediaAssets(companyId: string, query: MarketingMediaAssetQueryDto) {
    const data = await this.mediaAssets.list(companyId, query);
    return {
      ...data,
      items: (data.items ?? []).map((item: any) => this.normalizeMediaAssetUrls(item)),
    };
  }

  async listContentGallery(companyId: string) {
    const data = await this.mediaAssets.list(companyId, {
      active_only: true,
    } as MarketingMediaAssetQueryDto);

    return {
      ...data,
      items: (data.items ?? []).map((item: any) => {
        const normalized = this.normalizeMediaAssetUrls(item);
        return {
          ...normalized,
          approvedForPublicidad: true,
          origin: `${normalized.sourceType ?? ''}`.trim() || 'content-gallery',
          recommendedUse:
            `${normalized.relatedService ?? ''}`.trim() ||
            `${normalized.category ?? ''}`.trim() ||
            'General',
        };
      }),
    };
  }

  async createMediaAsset(companyId: string, dto: CreateMarketingMediaAssetDto, userId: string) {
    const created = await this.mediaAssets.create(companyId, dto);
    await this.log(companyId, 'MARKETING_MEDIA_ASSET_CREATED', 'Nuevo asset agregado en galería publicitaria', userId, {
      id: created.id,
      category: created.category,
    });
    return this.normalizeMediaAssetUrls(created);
  }

  async updateMediaAsset(companyId: string, id: string, dto: UpdateMarketingMediaAssetDto, userId: string) {
    const updated = await this.mediaAssets.update(companyId, id, dto);
    await this.log(companyId, 'MARKETING_MEDIA_ASSET_UPDATED', `Asset actualizado ${id}`, userId, dto);
    return this.normalizeMediaAssetUrls(updated);
  }

  async deleteMediaAsset(companyId: string, id: string, userId: string) {
    const removed = await this.mediaAssets.remove(companyId, id);
    await this.log(companyId, 'MARKETING_MEDIA_ASSET_DELETED', `Asset eliminado ${id}`, userId, null);
    return removed;
  }

  async listPublishedAssets(companyId: string) {
    const items = await this.prisma.marketingDailyStory.findMany({
      where: {
        companyId,
        status: 'APPROVED',
      },
      orderBy: [{ approvedAt: 'desc' }, { updatedAt: 'desc' }],
      include: {
        mediaAsset: true,
        approvedByUser: {
          select: {
            id: true,
            nombreCompleto: true,
          },
        },
      },
    });

    return {
      items: await Promise.all(items.map(async (item) => ({
        id: item.id,
        storyId: item.id,
        mediaAssetId: item.mediaAssetId ?? null,
        generatedImageUrl: await this.normalizeImageUrlAsync(item.generatedImageUrl),
        imageUrl: await this.normalizeImageUrlAsync(item.imageUrl),
        headline: item.title,
        shortText: item.shortText,
        cta: item.usedCTA ?? null,
        hashtags: item.hashtags,
        storyType: item.type,
        platform: 'PENDING_PLATFORM',
        status: item.status,
        approvedAt: item.approvedAt,
        publishedAt: null,
        createdAt: item.createdAt,
        updatedAt: item.updatedAt,
        date: item.date,
        mediaAsset: item.mediaAsset ? await this.normalizeMediaAssetUrlsAsync(item.mediaAsset) : null,
      }))),
    };
  }

  async resetClean(companyId: string, userId: string, dto: MarketingResetCleanDto) {
    const includeResearch = dto.includeResearch === true;
    const includeGeneratedImages = dto.includeGeneratedImages !== false;
    const includeDraftMedia = dto.includeMediaAssets ?? dto.includeDraftMedia ?? true;
    const includeApprovedStories = dto.includeApprovedStories === true;
    const date = dto.date ? this.parseDateOnly(dto.date) : null;

    const storiesWhere: any = {
      companyId,
      ...(date ? { date } : {}),
      ...(includeApprovedStories ? {} : { status: { not: 'APPROVED' } }),
    };

    const keptStoriesWhere: any = {
      companyId,
      ...(date ? { date } : {}),
      ...(includeApprovedStories ? { id: { in: [] } } : { status: 'APPROVED' }),
    };

    const candidateStories = await this.prisma.marketingDailyStory.findMany({
      where: storiesWhere,
      select: {
        id: true,
        status: true,
        generatedImageUrl: true,
        mediaAssetId: true,
      },
    });

    const publishedDraftsDeleted = candidateStories.filter((item) => item.status === 'APPROVED').length;

    const brokenMediaAssetIds = new Set<string>();
    const activeMediaIds = new Set(
      candidateStories
        .map((item) => (item.mediaAssetId || '').trim())
        .filter((id) => id.length > 0),
    );

    if (activeMediaIds.size > 0) {
      const existing = await this.prisma.marketingMediaAsset.findMany({
        where: {
          companyId,
          id: { in: [...activeMediaIds] },
        },
        select: { id: true },
      });
      const existingIds = new Set(existing.map((item) => item.id));
      for (const id of activeMediaIds) {
        if (!existingIds.has(id)) brokenMediaAssetIds.add(id);
      }
    }

    const generatedImagesDeleted = includeGeneratedImages
      ? candidateStories.filter((item) => (item.generatedImageUrl || '').trim().length > 0).length
      : 0;

    const [researchKeptCount, mediaAssetsTotalCount] = await Promise.all([
      this.prisma.marketingResearch.count({
        where: {
          companyId,
          ...(date ? { date } : {}),
        },
      }),
      this.prisma.marketingMediaAsset.count({ where: { companyId } }),
    ]);

    const deletionResult = await this.prisma.$transaction(async (tx) => {
      const activityLogsDeletedResult = await tx.marketingActivityLog.deleteMany({
        where: {
          companyId,
          action: {
            in: [
              'MARKETING_STORIES_GENERATED',
              'MARKETING_STORY_APPROVED',
              'MARKETING_STORY_REJECTED',
              'MARKETING_STORY_REGENERATED',
              'MARKETING_STORY_IMAGE_REGENERATED',
              'MARKETING_MEDIA_ASSET_USED',
            ],
          },
          ...(date ? { metadata: { path: ['date'], equals: this.toDateOnly(date) } as any } : {}),
        },
      });

      const storiesDeletedResult = await tx.marketingDailyStory.deleteMany({
        where: storiesWhere,
      });

      const approvedStoriesKept = await tx.marketingDailyStory.findMany({
        where: keptStoriesWhere,
        select: {
          id: true,
          mediaAssetId: true,
          generatedImageUrl: true,
          imageUrl: true,
        },
      });

      if (approvedStoriesKept.length > 0) {
        const referenced = approvedStoriesKept
          .map((item) => (item.mediaAssetId || '').trim())
          .filter((id) => id.length > 0);
        if (referenced.length > 0) {
          const existing = await tx.marketingMediaAsset.findMany({
            where: { companyId, id: { in: referenced } },
            select: { id: true },
          });
          const existingSet = new Set(existing.map((item) => item.id));
          const brokenStoryIds = approvedStoriesKept
            .filter((item) => !!item.mediaAssetId && !existingSet.has(item.mediaAssetId))
            .map((item) => item.id);
          if (brokenStoryIds.length > 0) {
            await tx.marketingDailyStory.updateMany({
              where: { id: { in: brokenStoryIds } },
              data: { mediaAssetId: null },
            });
          }
        }
      }

      if (includeGeneratedImages && includeApprovedStories) {
        await tx.marketingDailyStory.updateMany({
          where: {
            companyId,
            ...(date ? { date } : {}),
            OR: [
              { generatedImageUrl: '' },
              { generatedImageUrl: null },
            ],
          },
          data: {
            generatedImageUrl: null,
          },
        });
      }

      let draftGeneratedAssetsDeleted = 0;
      if (includeDraftMedia && includeGeneratedImages) {
        const candidates = await tx.marketingMediaAsset.findMany({
          where: {
            companyId,
            OR: [
              { fileName: { startsWith: 'ai-' } },
              { description: { contains: 'Generada automaticamente para estado' } },
            ],
          },
          select: { id: true },
        });

        if (candidates.length > 0) {
          const candidateIds = candidates.map((item) => item.id);
          const stillReferenced = await tx.marketingDailyStory.findMany({
            where: {
              companyId,
              mediaAssetId: { in: candidateIds },
            },
            select: { mediaAssetId: true },
          });
          const referencedSet = new Set(
            stillReferenced
              .map((item) => (item.mediaAssetId || '').trim())
              .filter((id) => id.length > 0),
          );
          const deletableIds = candidateIds.filter((id) => !referencedSet.has(id));
          if (deletableIds.length > 0) {
            const deleteAssetsResult = await tx.marketingMediaAsset.deleteMany({
              where: {
                companyId,
                id: { in: deletableIds },
              },
            });
            draftGeneratedAssetsDeleted = deleteAssetsResult.count;
          }
        }
      }

      let researchDeleted = 0;
      if (includeResearch) {
        const deleted = await tx.marketingResearch.deleteMany({
          where: {
            companyId,
            ...(date ? { date } : {}),
          },
        });
        researchDeleted = deleted.count;
      }

      await tx.marketingActivityLog.create({
        data: {
          companyId,
          action: 'MARKETING_RESET_CLEAN',
          description: 'Reset limpio de Publicidad ejecutado',
          userId,
          metadata: {
            includeResearch,
            includeDraftMedia,
            includeGeneratedImages,
            includeApprovedStories,
            date: date ? this.toDateOnly(date) : null,
            brokenMediaAssetRefsDetected: brokenMediaAssetIds.size,
            storiesTargeted: candidateStories.length,
            researchDeleted,
            draftGeneratedAssetsDeleted,
          },
        },
      });

      return {
        storiesDeleted: storiesDeletedResult.count,
        activityLogsDeleted: activityLogsDeletedResult.count,
        publishedDraftsDeleted,
        draftGeneratedAssetsDeleted,
        researchDeleted,
      };
    });

    return {
      storiesDeleted: deletionResult.storiesDeleted,
      generatedImagesDeleted: generatedImagesDeleted + deletionResult.draftGeneratedAssetsDeleted,
      activityLogsDeleted: deletionResult.activityLogsDeleted,
      publishedDraftsDeleted: deletionResult.publishedDraftsDeleted,
      researchKept: includeResearch ? Math.max(0, researchKeptCount - deletionResult.researchDeleted) : researchKeptCount,
      mediaAssetsKept: Math.max(0, mediaAssetsTotalCount - deletionResult.draftGeneratedAssetsDeleted),
      dateScope: date ? this.toDateOnly(date) : null,
      options: {
        includeResearch,
        includeDraftMedia,
        includeGeneratedImages,
        includeApprovedStories,
      },
    };
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

  private pickLatestStoryPerType<T extends { type: MarketingStoryType }>(rows: T[]) {
    const byType = new Map<MarketingStoryType, T>();
    for (const row of rows) {
      if (!byType.has(row.type)) {
        byType.set(row.type, row);
      }
    }

    const ordered: MarketingStoryType[] = [
      MarketingStoryType.SALES,
      MarketingStoryType.TRUST,
      MarketingStoryType.EDUCATIONAL,
    ];

    return ordered
      .map((type) => byType.get(type))
      .filter((item): item is T => !!item);
  }

  private getStoryMissingFields(story: {
    title: string;
    shortText: string;
    usedCTA: string | null;
    imagePrompt: string | null;
    imageUrl: string | null;
    generatedImageUrl: string | null;
    mediaAssetId: string | null;
  }) {
    const missing: string[] = [];
    const hasFinalImage =
      `${story.generatedImageUrl ?? ''}`.trim().length > 0 ||
      `${story.imageUrl ?? ''}`.trim().length > 0;
    if (!hasFinalImage) missing.push('imagen final');

    if (`${story.imagePrompt ?? ''}`.trim().length == 0) missing.push('prompt');

    const hasCopy =
      `${story.title ?? ''}`.trim().length > 0 &&
      `${story.shortText ?? ''}`.trim().length > 0 &&
      `${story.usedCTA ?? ''}`.trim().length > 0;
    if (!hasCopy) missing.push('copy');

    return missing;
  }

  private toDateOnly(value: Date) {
    const year = value.getUTCFullYear();
    const month = `${value.getUTCMonth() + 1}`.padStart(2, '0');
    const day = `${value.getUTCDate()}`.padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  private normalizeImageUrl(value: string | null | undefined) {
    const raw = `${value ?? ''}`.trim();
    if (!raw) return '';
    if (raw.startsWith('data:image/')) return raw;
    return this.marketingStorage.getPublicUrl(raw);
  }

  private async normalizeImageUrlAsync(value: string | null | undefined) {
    const raw = `${value ?? ''}`.trim();
    if (!raw) return '';
    if (raw.startsWith('data:image/')) return raw;
    return this.marketingStorage.getPublicUrlAsync(raw);
  }

  private normalizeMediaAssetUrls<T extends Record<string, any>>(asset: T): T {
    const normalizedFileUrl = this.normalizeImageUrl(asset.fileUrl);
    const normalizedThumb = this.normalizeImageUrl(asset.thumbnailUrl);
    return {
      ...asset,
      fileUrl: normalizedFileUrl,
      thumbnailUrl: normalizedThumb || null,
      sourceType: this.inferAssetSourceType(normalizedFileUrl, asset.fileName, asset.tags),
    };
  }

  private async normalizeMediaAssetUrlsAsync<T extends Record<string, any>>(asset: T): Promise<T> {
    const normalizedFileUrl = await this.normalizeImageUrlAsync(asset.fileUrl);
    const normalizedThumb = await this.normalizeImageUrlAsync(asset.thumbnailUrl);
    return {
      ...asset,
      fileUrl: normalizedFileUrl,
      thumbnailUrl: normalizedThumb || null,
      sourceType: this.inferAssetSourceType(normalizedFileUrl, asset.fileName, asset.tags),
    };
  }

  private normalizeStoryUrls<T extends Record<string, any>>(story: T): T {
    return {
      ...story,
      imageUrl: this.normalizeImageUrl(story.imageUrl),
      generatedImageUrl: this.normalizeImageUrl(story.generatedImageUrl),
      mediaAsset: story.mediaAsset ? this.normalizeMediaAssetUrls(story.mediaAsset) : null,
    };
  }

  private async normalizeStoryUrlsAsync<T extends Record<string, any>>(story: T): Promise<T> {
    return {
      ...story,
      imageUrl: await this.normalizeImageUrlAsync(story.imageUrl),
      generatedImageUrl: await this.normalizeImageUrlAsync(story.generatedImageUrl),
      mediaAsset: story.mediaAsset ? await this.normalizeMediaAssetUrlsAsync(story.mediaAsset) : null,
    };
  }

  private inferAssetSourceType(fileUrl: string, fileName?: string | null, tags?: unknown) {
    const url = (fileUrl || '').toLowerCase();
    const name = `${fileName ?? ''}`.toLowerCase();
    const tagList = Array.isArray(tags)
      ? tags.map((tag) => `${tag}`.toLowerCase())
      : [];
    const generatedByUrl =
      url.includes('/marketing/generated/') ||
      url.includes('/generated/') ||
      name.startsWith('ai-');
    const generatedByTags = tagList.some((tag) => ['ia', 'ai', 'generada', 'generated'].includes(tag));
    if (generatedByUrl || generatedByTags) return 'GENERATED_AI';

    const isProduct = tagList.some((tag) =>
      [
        'catalogo',
        'imagen-producto',
        'producto-catalogo',
      ].includes(tag),
    );
    if (isProduct) return 'PRODUCT_IMAGE';

    const isFileExplorer = tagList.some((tag) =>
      [
        'explorador-archivo',
        'archivo',
        'manual-upload',
      ].includes(tag),
    );
    if (isFileExplorer) return 'FILE_EXPLORER';

    const isGallery = tagList.some((tag) =>
      [
        'galeria-media',
        'media-gallery',
        'galeria-publicidad',
      ].includes(tag),
    );
    if (isGallery) return 'GALLERY_IMAGE';

    if (url.includes('/catalog/') || url.includes('/products/')) {
      return 'PRODUCT_IMAGE';
    }
    if (url.includes('/upload') || url.includes('/media/')) {
      return 'FILE_EXPLORER';
    }

    return 'GALLERY_IMAGE';
  }
}
