import {
  BadRequestException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import {
  MarketingCampaignCurrency,
  MarketingCampaignPhase,
  MarketingCampaignStatus,
  Prisma,
} from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import {
  CreateMetaCampaignDto,
  UpdateMarketingCampaignDto,
  UploadCampaignDesignDto,
} from './dto/marketing-campaign.dto';
import { MarketingMediaAssetService } from './marketing-media-asset.service';
import { MarketingMetaAdsService } from './marketing-meta-ads.service';
import { MarketingStorageService } from './marketing-storage.service';

@Injectable()
export class MarketingCampaignService {
  private static readonly WHATSAPP_MESSAGES_OBJECTIVE = 'OUTCOME_ENGAGEMENT';

  constructor(
    private readonly prisma: PrismaService,
    private readonly mediaAssets: MarketingMediaAssetService,
    private readonly metaAds: MarketingMetaAdsService,
    private readonly storage: MarketingStorageService,
  ) {}

  async list(companyId: string, date?: Date) {
    const items = await this.prisma.marketingAdCampaign.findMany({
      where: {
        companyId,
        ...(date
          ? {
              date,
            }
          : {}),
      },
      include: {
        mediaAsset: true,
        research: {
          select: {
            id: true,
            mainFocus: true,
            city: true,
            country: true,
            confidenceScore: true,
            createdAt: true,
          },
        },
      },
      orderBy: [{ updatedAt: 'desc' }, { createdAt: 'desc' }],
    });

    return {
      items,
      config: await this.metaAds.debugAdsConfig(),
    };
  }

  async details(companyId: string, id: string) {
    const campaign = await this.ensure(companyId, id);
    return {
      ...campaign,
      technical: {
        metaCampaignId: campaign.metaCampaignId,
        metaAdSetId: campaign.metaAdSetId,
        metaCreativeId: campaign.metaCreativeId,
        metaAdId: campaign.metaAdId,
        metaStatus: campaign.metaStatus,
        metaError: campaign.metaError,
        metaErrorCode: campaign.metaErrorCode,
        metaErrorSubcode: campaign.metaErrorSubcode,
        fbtraceId: campaign.fbtraceId,
      },
    };
  }

  async generateMissing(companyId: string, userId: string, date: Date) {
    const existing = await this.prisma.marketingAdCampaign.findFirst({
      where: {
        companyId,
        date,
      },
      orderBy: { createdAt: 'desc' },
    });
    if (existing) {
      return existing;
    }

    const [research, mediaAsset] = await Promise.all([
      this.prisma.marketingResearch.findFirst({
        where: {
          companyId,
          status: 'APPROVED',
        },
        orderBy: { createdAt: 'desc' },
      }),
      this.prisma.marketingMediaAsset.findFirst({
        where: {
          companyId,
          isActive: true,
        },
        orderBy: [{ isFeatured: 'desc' }, { useCount: 'desc' }, { updatedAt: 'desc' }],
      }),
    ]);

    const recommendedAudience = this.buildAudienceRecommendation(
      mediaAsset?.category ?? '',
      research?.city ?? 'Higuey',
      research?.country ?? 'República Dominicana',
    );

    const campaign = await this.prisma.marketingAdCampaign.create({
      data: {
        companyId,
        date,
        campaignType: 'META_ADS',
        status: MarketingCampaignStatus.DRAFT,
        phase: MarketingCampaignPhase.DESIGN,
        baseImageUrl: mediaAsset ? this.storage.getPublicUrl(mediaAsset.fileUrl) : null,
        galleryAssetId: mediaAsset?.id ?? null,
        aiResearchId: research?.id ?? null,
        aiAngle:
          `${research?.mainFocus ?? ''}`.trim() ||
          `Enfoque comercial para ${mediaAsset?.category ?? 'producto principal'}`,
        recommendedAudienceJson: recommendedAudience as Prisma.InputJsonValue,
        finalAudienceJson: recommendedAudience as Prisma.InputJsonValue,
        currency: MarketingCampaignCurrency.DOP,
        cta: 'WHATSAPP_MESSAGE',
        dailyBudget: new Prisma.Decimal(500),
        whatsappMessageTemplate: 'Hola, vi su anuncio y deseo información',
        createdByUserId: userId || null,
        updatedByUserId: userId || null,
      },
      include: {
        mediaAsset: true,
        research: true,
      },
    });

    return campaign;
  }

  async confirmBaseImage(companyId: string, id: string, userId: string) {
    const campaign = await this.ensure(companyId, id);
    if (!campaign.baseImageUrl) {
      throw new BadRequestException('Debes seleccionar una imagen base antes de confirmar.');
    }

    return this.prisma.marketingAdCampaign.update({
      where: { id },
      data: {
        phase: MarketingCampaignPhase.COPY_SEGMENTATION,
        updatedByUserId: userId || null,
      },
    });
  }

  async changeBaseImage(companyId: string, id: string, mediaAssetId: string, userId: string) {
    await this.ensure(companyId, id);
    const asset = await this.mediaAssets.ensure(companyId, mediaAssetId);

    return this.prisma.marketingAdCampaign.update({
      where: { id },
      data: {
        galleryAssetId: asset.id,
        baseImageUrl: this.storage.getPublicUrl(asset.fileUrl),
        phase: MarketingCampaignPhase.DESIGN,
        updatedByUserId: userId || null,
      },
    });
  }

  async uploadDesign(companyId: string, id: string, dto: UploadCampaignDesignDto, userId: string) {
    const campaign = await this.ensure(companyId, id);
    const finalDesignUrl = this.storage.getPublicUrl(dto.finalDesignUrl.trim());
    if (!finalDesignUrl.startsWith('http://') && !finalDesignUrl.startsWith('https://')) {
      throw new BadRequestException(
        'No se pudo crear Creative porque la imagen no es pública HTTPS/HTTP.',
      );
    }

    const fileName = (dto.fileName ?? '').trim() || this.extractName(finalDesignUrl);
    const mimeType = (dto.mimeType ?? '').trim() || this.inferMime(fileName);

    const asset = await this.prisma.marketingMediaAsset.create({
      data: {
        companyId,
        fileUrl: finalDesignUrl,
        thumbnailUrl: null,
        fileName,
        mimeType,
        category: 'campana publicitaria',
        relatedService: 'marketing-ads',
        tags: ['campana', 'marketing_campaign_design', `origin:${campaign.id}`],
        description: `Diseño final de campaña ${campaign.id}`,
        isActive: true,
        isFeatured: false,
      },
    });

    return this.prisma.marketingAdCampaign.update({
      where: { id },
      data: {
        finalDesignUrl,
        galleryAssetId: asset.id,
        phase: MarketingCampaignPhase.COPY_SEGMENTATION,
        status: MarketingCampaignStatus.DRAFT,
        updatedByUserId: userId || null,
      },
      include: {
        mediaAsset: true,
      },
    });
  }

  async regenerateCopy(companyId: string, id: string, userId: string) {
    const campaign = await this.ensure(companyId, id);
    if (!campaign.finalDesignUrl && !campaign.baseImageUrl) {
      throw new BadRequestException('Sube primero el diseño final para generar copy y segmentación.');
    }

    const audience = this.asRecord(campaign.finalAudienceJson) ??
      this.asRecord(campaign.recommendedAudienceJson) ??
      this.buildAudienceRecommendation('servicios de seguridad', 'Higuey', 'La Altagracia');

    const angle = `${campaign.aiAngle ?? ''}`.trim() || 'Seguridad práctica y resultados reales.';
    const locationLabel = `${audience['city'] ?? 'Higuey'}, ${audience['region'] ?? 'La Altagracia'}`;

    return this.prisma.marketingAdCampaign.update({
      where: { id },
      data: {
        headline: campaign.headline || 'Protege tu hogar o negocio desde hoy',
        primaryText:
          campaign.primaryText ||
          `Instalación profesional y rápida. ${angle} Atención directa por WhatsApp para cotizar hoy.`,
        description:
          campaign.description ||
          `Campaña enfocada en ${locationLabel} con audiencia de alta intención de compra.`,
        cta: campaign.cta || 'WHATSAPP_MESSAGE',
        hashtags:
          campaign.hashtags.length > 0
            ? campaign.hashtags
            : ['#Seguridad', '#Camaras', '#Higuey', '#Fulltech'],
        aiAngle: angle,
        recommendedAudienceJson: audience as Prisma.InputJsonValue,
        phase: MarketingCampaignPhase.PUBLISH,
        status: MarketingCampaignStatus.READY,
        updatedByUserId: userId || null,
      },
    });
  }

  async update(companyId: string, id: string, dto: UpdateMarketingCampaignDto, userId: string) {
    await this.ensure(companyId, id);

    const data: Prisma.MarketingAdCampaignUncheckedUpdateInput = {
      ...(dto.status ? { status: dto.status } : {}),
      ...(dto.phase ? { phase: dto.phase } : {}),
      ...(dto.headline !== undefined ? { headline: dto.headline?.trim() || null } : {}),
      ...(dto.primaryText !== undefined ? { primaryText: dto.primaryText?.trim() || null } : {}),
      ...(dto.description !== undefined ? { description: dto.description?.trim() || null } : {}),
      ...(dto.cta !== undefined ? { cta: dto.cta?.trim() || null } : {}),
      ...(dto.hashtags !== undefined
        ? {
            hashtags: dto.hashtags
              .map((item) => item.trim())
              .filter((item) => item.length > 0),
          }
        : {}),
      ...(dto.aiAngle !== undefined ? { aiAngle: dto.aiAngle?.trim() || null } : {}),
      ...(dto.recommendedAudienceJson !== undefined
        ? { recommendedAudienceJson: dto.recommendedAudienceJson as Prisma.InputJsonValue }
        : {}),
      ...(dto.finalAudienceJson !== undefined
        ? { finalAudienceJson: dto.finalAudienceJson as Prisma.InputJsonValue }
        : {}),
      ...(dto.dailyBudget !== undefined ? { dailyBudget: new Prisma.Decimal(dto.dailyBudget) } : {}),
      ...(dto.totalBudget !== undefined
        ? {
            totalBudget: dto.totalBudget > 0 ? new Prisma.Decimal(dto.totalBudget) : null,
          }
        : {}),
      ...(dto.currency ? { currency: dto.currency } : {}),
      ...(dto.whatsappPhone !== undefined ? { whatsappPhone: dto.whatsappPhone?.trim() || null } : {}),
      ...(dto.whatsappMessageTemplate !== undefined
        ? { whatsappMessageTemplate: dto.whatsappMessageTemplate?.trim() || null }
        : {}),
      ...(dto.destinationUrl !== undefined ? { destinationUrl: dto.destinationUrl?.trim() || null } : {}),
      ...(dto.startTime !== undefined
        ? { startTime: dto.startTime ? new Date(dto.startTime) : null }
        : {}),
      ...(dto.endTime !== undefined ? { endTime: dto.endTime ? new Date(dto.endTime) : null } : {}),
      ...(dto.keepRunningUntilPaused !== undefined
        ? { keepRunningUntilPaused: dto.keepRunningUntilPaused }
        : {}),
      updatedByUserId: userId || null,
    };

    return this.prisma.marketingAdCampaign.update({
      where: { id },
      data,
    });
  }

  async createMetaCampaign(companyId: string, id: string, dto: CreateMetaCampaignDto, userId: string) {
    const campaign = await this.ensure(companyId, id);

    const dailyBudget = Number(campaign.dailyBudget ?? 0);
    if (!(dailyBudget > 0)) {
      throw new BadRequestException('No se pudo crear el Ad Set porque el presupuesto es menor al mínimo.');
    }

    const audience = this.asRecord(campaign.finalAudienceJson) ??
      this.asRecord(campaign.recommendedAudienceJson) ??
      this.buildAudienceRecommendation('servicios', 'Higuey', 'La Altagracia');

    const targeting = this.mapAudienceToMetaTargeting(audience);

    try {
      const ids = await this.metaAds.createCampaignFlow({
        name: `${campaign.headline ?? 'Campaña'} ${new Date().toISOString().substring(0, 10)}`,
        objective:
          (dto.objective ?? MarketingCampaignService.WHATSAPP_MESSAGES_OBJECTIVE)
            .trim() || MarketingCampaignService.WHATSAPP_MESSAGES_OBJECTIVE,
        dailyBudget,
        totalBudget: campaign.totalBudget ? Number(campaign.totalBudget) : null,
        headline: campaign.headline ?? 'Campaña Fulltech',
        primaryText: campaign.primaryText ?? 'Conoce nuestra solución ahora mismo.',
        description: campaign.description,
        cta: campaign.cta ?? 'WHATSAPP_MESSAGE',
        destinationUrl: campaign.destinationUrl,
        whatsappPhone: campaign.whatsappPhone,
        startTime: campaign.startTime,
        endTime: campaign.endTime,
        targeting,
      });

      const status = dto.activateAfterCreate ? MarketingCampaignStatus.ACTIVE : MarketingCampaignStatus.PAUSED;

      if (dto.activateAfterCreate) {
        await this.metaAds.activateCampaign(ids.campaignId, ids.adSetId, ids.adId);
      }

      return this.prisma.marketingAdCampaign.update({
        where: { id },
        data: {
          status,
          phase: MarketingCampaignPhase.PUBLISH,
          metaCampaignId: ids.campaignId,
          metaAdSetId: ids.adSetId,
          metaCreativeId: ids.creativeId,
          metaAdId: ids.adId,
          metaStatus: dto.activateAfterCreate ? 'ACTIVE' : 'PAUSED',
          metaError: null,
          metaErrorCode: null,
          metaErrorSubcode: null,
          fbtraceId: null,
          publishedAt: new Date(),
          updatedByUserId: userId || null,
        },
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Error al crear campaña en Meta Ads';
      return this.prisma.marketingAdCampaign.update({
        where: { id },
        data: {
          status: MarketingCampaignStatus.ERROR,
          metaStatus: 'ERROR',
          metaError: message,
          updatedByUserId: userId || null,
        },
      });
    }
  }

  async activate(companyId: string, id: string, userId: string) {
    const campaign = await this.ensure(companyId, id);
    if (!campaign.metaCampaignId) {
      throw new ServiceUnavailableException('Debes crear primero la campaña en Meta Ads.');
    }

    await this.metaAds.activateCampaign(
      campaign.metaCampaignId,
      campaign.metaAdSetId,
      campaign.metaAdId,
    );

    return this.prisma.marketingAdCampaign.update({
      where: { id },
      data: {
        status: MarketingCampaignStatus.ACTIVE,
        metaStatus: 'ACTIVE',
        updatedByUserId: userId || null,
      },
    });
  }

  async pause(companyId: string, id: string, userId: string) {
    const campaign = await this.ensure(companyId, id);
    if (!campaign.metaCampaignId) {
      throw new ServiceUnavailableException('No existe Campaign ID para pausar.');
    }

    await this.metaAds.pauseCampaign(
      campaign.metaCampaignId,
      campaign.metaAdSetId,
      campaign.metaAdId,
    );

    return this.prisma.marketingAdCampaign.update({
      where: { id },
      data: {
        status: MarketingCampaignStatus.PAUSED,
        metaStatus: 'PAUSED',
        updatedByUserId: userId || null,
      },
    });
  }

  async reject(companyId: string, id: string, userId: string) {
    await this.ensure(companyId, id);
    return this.prisma.marketingAdCampaign.update({
      where: { id },
      data: {
        status: MarketingCampaignStatus.REJECTED,
        updatedByUserId: userId || null,
      },
    });
  }

  async duplicate(companyId: string, id: string, userId: string) {
    const source = await this.ensure(companyId, id);
    return this.prisma.marketingAdCampaign.create({
      data: {
        companyId,
        date: new Date(source.date),
        campaignType: source.campaignType,
        status: MarketingCampaignStatus.DRAFT,
        phase: MarketingCampaignPhase.DESIGN,
        baseImageUrl: source.baseImageUrl,
        finalDesignUrl: source.finalDesignUrl,
        galleryAssetId: source.galleryAssetId,
        headline: source.headline,
        primaryText: source.primaryText,
        description: source.description,
        cta: source.cta,
        hashtags: source.hashtags,
        aiAngle: source.aiAngle,
        aiResearchId: source.aiResearchId,
        recommendedAudienceJson:
          source.recommendedAudienceJson === null
            ? Prisma.JsonNull
            : (source.recommendedAudienceJson as Prisma.InputJsonValue),
        finalAudienceJson:
          source.finalAudienceJson === null
            ? Prisma.JsonNull
            : (source.finalAudienceJson as Prisma.InputJsonValue),
        dailyBudget: source.dailyBudget,
        totalBudget: source.totalBudget,
        currency: source.currency,
        whatsappPhone: source.whatsappPhone,
        whatsappMessageTemplate: source.whatsappMessageTemplate,
        destinationUrl: source.destinationUrl,
        startTime: source.startTime,
        endTime: source.endTime,
        keepRunningUntilPaused: source.keepRunningUntilPaused,
        createdByUserId: userId || null,
        updatedByUserId: userId || null,
      },
    });
  }

  private async ensure(companyId: string, id: string) {
    const campaign = await this.prisma.marketingAdCampaign.findFirst({
      where: { id, companyId },
      include: {
        mediaAsset: true,
        research: true,
      },
    });
    if (!campaign) {
      throw new NotFoundException('Campaña no encontrada.');
    }
    return campaign;
  }

  private buildAudienceRecommendation(category: string, city: string, region: string) {
    const label = `${category}`.toLowerCase();
    if (label.includes('camara') || label.includes('seguridad')) {
      return {
        city,
        region,
        radiusKm: 15,
        ageMin: 25,
        ageMax: 60,
        gender: 'ALL',
        interests: [
          'seguridad del hogar',
          'cámaras de seguridad',
          'negocios',
          'tecnología',
          'ferretería',
        ],
        audience: [
          'dueños de negocios',
          'hogares',
          'colmados',
          'oficinas',
          'residenciales',
        ],
        objective: MarketingCampaignService.WHATSAPP_MESSAGES_OBJECTIVE,
      };
    }

    if (label.includes('motor') || label.includes('porton')) {
      return {
        city,
        region,
        radiusKm: 20,
        ageMin: 30,
        ageMax: 65,
        gender: 'ALL',
        interests: [
          'automatización',
          'seguridad residencial',
          'construcción',
          'portones eléctricos',
          'ferretería',
        ],
        audience: ['propietarios residenciales', 'constructores', 'comunidades cerradas'],
        objective: MarketingCampaignService.WHATSAPP_MESSAGES_OBJECTIVE,
      };
    }

    return {
      city,
      region,
      radiusKm: 10,
      ageMin: 25,
      ageMax: 60,
      gender: 'ALL',
      interests: ['tecnología', 'servicios', 'seguridad', 'hogar'],
      audience: ['personas con intención de compra'],
      objective: MarketingCampaignService.WHATSAPP_MESSAGES_OBJECTIVE,
    };
  }

  private mapAudienceToMetaTargeting(audience: Record<string, unknown>) {
    const ageMin = Number(audience.ageMin ?? 24);
    const ageMax = Number(audience.ageMax ?? 60);
    const city = `${audience.city ?? 'Higuey'}`.trim() || 'Higuey';
    const region = `${audience.region ?? 'La Altagracia'}`.trim() || 'La Altagracia';

    return {
      age_min: Math.max(18, ageMin),
      age_max: Math.max(Math.max(18, ageMin), ageMax),
      geo_locations: {
        cities: [
          {
            key: city,
            radius: Number(audience.radiusKm ?? 15),
            distance_unit: 'kilometer',
          },
        ],
        regions: [{ key: region }],
      },
      publisher_platforms: ['facebook', 'instagram'],
      facebook_positions: ['feed', 'story'],
      instagram_positions: ['stream', 'story'],
    };
  }

  private asRecord(value: unknown): Record<string, unknown> | null {
    if (typeof value !== 'object' || value === null || Array.isArray(value)) return null;
    return value as Record<string, unknown>;
  }

  private extractName(url: string) {
    try {
      const parsed = new URL(url);
      const name = parsed.pathname.split('/').filter(Boolean).pop();
      return name?.trim() || 'campaign-design.jpg';
    } catch {
      return 'campaign-design.jpg';
    }
  }

  private inferMime(fileName: string) {
    const lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
