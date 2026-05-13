import {
  BadRequestException,
  Injectable,
  Logger,
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

type CampaignVisionCopy = {
  detectedProduct: string;
  headline: string;
  primaryText: string;
  description: string;
  hashtags: string[];
};

@Injectable()
export class MarketingCampaignService {
  private static readonly WHATSAPP_MESSAGES_OBJECTIVE = 'OUTCOME_ENGAGEMENT';
  private readonly logger = new Logger(MarketingCampaignService.name);

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

    const mediaCategory = `${campaign.mediaAsset?.category ?? 'servicios de seguridad'}`.trim();
    const mediaDescription = `${campaign.mediaAsset?.description ?? ''}`.trim();
    const mediaFileName = `${campaign.mediaAsset?.fileName ?? ''}`.trim();
    const mediaTags = this.jsonStrings(campaign.mediaAsset?.tags);
    const research = campaign.research;
    const researchAngle = this.firstText([
      research?.mainFocus,
      ...this.jsonStrings(research?.strongAngles),
      research?.contentOpportunities,
      research?.marketSummary,
      campaign.aiAngle,
    ]);
    const angle = researchAngle || 'Seguridad práctica y resultados reales.';
    const locationLabel = `${audience['city'] ?? 'Higuey'}, ${audience['region'] ?? 'La Altagracia'}`;
    const imageUrl = `${campaign.finalDesignUrl ?? campaign.baseImageUrl ?? ''}`.trim();
    const visionCopy = await this.generateCampaignVisionCopy({
      imageUrl,
      mediaCategory,
      mediaDescription,
      mediaFileName,
      mediaTags,
      researchAngle: angle,
      locationLabel,
    });
    const commercialIntent = this.detectCommercialIntent(
      visionCopy?.detectedProduct || mediaCategory,
      visionCopy?.description || mediaDescription,
      visionCopy?.hashtags?.length ? visionCopy.hashtags : mediaTags,
      angle,
    );
    const fallbackCommercialIntent = this.detectCommercialIntent(
      mediaCategory,
      mediaDescription,
      mediaTags,
      angle,
    );
    const salesStrategy = this.buildCampaignSalesStrategy(commercialIntent, angle, locationLabel);
    const fallbackHeadline = this.buildCampaignHeadline(mediaCategory, fallbackCommercialIntent, `${audience['city'] ?? 'Higuey'}`);
    const fallbackPrimaryText = this.buildCampaignPrimaryText({
      category: mediaCategory,
      commercialIntent: fallbackCommercialIntent,
      angle,
      salesStrategy,
      locationLabel,
      mediaDescription,
      mediaFileName,
    });
    const fallbackDescription = this.buildCampaignDescription(mediaCategory, fallbackCommercialIntent, locationLabel, salesStrategy);
    const headline = visionCopy?.headline || fallbackHeadline;
    const primaryText = visionCopy?.primaryText || fallbackPrimaryText;
    const description = visionCopy?.description || fallbackDescription;
    const hashtags = visionCopy?.hashtags?.length
      ? this.normalizeHashtags(visionCopy.hashtags)
      : this.buildCampaignHashtags(mediaCategory, `${audience['city'] ?? 'Higuey'}`, mediaTags);
    const aiAngle = visionCopy?.detectedProduct
      ? `${angle} Producto detectado en imagen: ${visionCopy.detectedProduct}`
      : angle;

    return this.prisma.marketingAdCampaign.update({
      where: { id },
      data: {
        headline,
        primaryText,
        description,
        cta: 'WHATSAPP_MESSAGE',
        hashtags,
        aiAngle,
        recommendedAudienceJson: audience as Prisma.InputJsonValue,
        phase: MarketingCampaignPhase.PUBLISH,
        status: MarketingCampaignStatus.READY,
        updatedByUserId: userId || null,
      },
    });
  }

  private firstText(values: Array<string | null | undefined>) {
    for (const value of values) {
      const clean = `${value ?? ''}`.trim();
      if (clean) return clean;
    }
    return '';
  }

  private jsonStrings(value: unknown) {
    if (!Array.isArray(value)) return [];
    return value
      .map((item) => `${item ?? ''}`.trim())
      .filter((item) => item.length > 0);
  }

  private async generateCampaignVisionCopy(input: {
    imageUrl: string;
    mediaCategory: string;
    mediaDescription: string;
    mediaFileName: string;
    mediaTags: string[];
    researchAngle: string;
    locationLabel: string;
  }): Promise<CampaignVisionCopy | null> {
    if (!input.imageUrl) return null;

    const envKey = (process.env.OPENAI_API_KEY ?? '').trim();
    let apiKey = envKey;
    let model = (process.env.OPENAI_MODEL ?? '').trim() || 'gpt-4o';
    let companyName = 'FULLTECH';

    if (!apiKey) {
      try {
        const appConfig = await this.prisma.appConfig.findUnique({
          where: { id: 'global' },
          select: { openAiApiKey: true, openAiModel: true, companyName: true },
        });
        apiKey = (appConfig?.openAiApiKey ?? '').trim();
        model = (appConfig?.openAiModel ?? '').trim() || model;
        companyName = (appConfig?.companyName ?? '').trim() || companyName;
      } catch (error) {
        this.logger.warn(
          `[campaign-vision-copy] No se pudo leer appConfig: ${error instanceof Error ? error.message : String(error)}`,
        );
      }
    }

    if (!apiKey) {
      this.logger.warn('[campaign-vision-copy] No OpenAI API key configured; using metadata fallback.');
      return null;
    }

    const systemPrompt = `Eres un estratega senior de Meta Ads para ${companyName} en Higüey, República Dominicana. Analizas la imagen REAL seleccionada para una campaña de WhatsApp Messages y generas copy de venta SOLO para el producto o servicio que se ve en la imagen. Nunca uses un producto distinto al detectado visualmente. Responde solo JSON válido.`;
    const userPrompt = `Analiza esta imagen seleccionada para la campaña: ${input.imageUrl}

Contexto de investigación: ${input.researchAngle}
Zona objetivo: ${input.locationLabel}
Metadata disponible, solo como apoyo si coincide con la imagen:
- categoría: ${input.mediaCategory}
- descripción: ${input.mediaDescription}
- archivo: ${input.mediaFileName}
- tags: ${input.mediaTags.join(', ')}

Genera copy profesional de venta para WhatsApp Messages. Debe ser llamativo, local, orientado a vender, con oferta/urgencia natural y CTA de mensaje. Si visualmente ves cámaras, habla de cámaras; si ves motor de portón, habla de motor; si ves alarma, habla de alarma.

Devuelve exactamente este JSON:
{
  "detectedProduct": "producto o servicio visualmente detectado",
  "headline": "titular vendedor de máximo 75 caracteres",
  "primaryText": "texto principal de 2 a 3 frases para vender por WhatsApp, acorde a la imagen y la investigación",
  "description": "descripción corta de máximo 120 caracteres",
  "hashtags": ["#hashtag1", "#hashtag2", "#hashtag3", "#hashtag4"]
}`;

    const modelCandidates = [model, 'gpt-4o', 'gpt-4o-mini'].filter((value, index, values) => values.indexOf(value) === index);
    for (const candidate of modelCandidates) {
      try {
        const response = await fetch('https://api.openai.com/v1/chat/completions', {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${apiKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            model: candidate,
            temperature: 0.35,
            messages: [
              { role: 'system', content: systemPrompt },
              {
                role: 'user',
                content: [
                  { type: 'image_url', image_url: { url: input.imageUrl, detail: 'high' } },
                  { type: 'text', text: userPrompt },
                ],
              },
            ],
          }),
        });

        if (!response.ok) {
          this.logger.warn(`[campaign-vision-copy] OpenAI HTTP ${response.status} with model ${candidate}`);
          continue;
        }

        const payload = (await response.json()) as { choices?: Array<{ message?: { content?: string } }> };
        const raw = payload.choices?.[0]?.message?.content?.trim() ?? '';
        const jsonMatch = raw.match(/\{[\s\S]*\}/);
        if (!jsonMatch) {
          this.logger.warn(`[campaign-vision-copy] OpenAI response without JSON using ${candidate}`);
          continue;
        }

        const parsed = JSON.parse(jsonMatch[0]) as Record<string, unknown>;
        const generated: CampaignVisionCopy = {
          detectedProduct: this.cleanVisionString(parsed.detectedProduct),
          headline: this.cleanVisionString(parsed.headline).substring(0, 90),
          primaryText: this.cleanVisionString(parsed.primaryText),
          description: this.cleanVisionString(parsed.description).substring(0, 140),
          hashtags: Array.isArray(parsed.hashtags)
            ? this.normalizeHashtags(parsed.hashtags.map((item) => `${item ?? ''}`))
            : [],
        };

        if (generated.detectedProduct && generated.headline && generated.primaryText && generated.description) {
          this.logger.log(
            `[campaign-vision-copy] Copy generado desde imagen. Producto detectado: ${generated.detectedProduct}. Modelo: ${candidate}`,
          );
          return generated;
        }
      } catch (error) {
        this.logger.warn(
          `[campaign-vision-copy] Error con modelo ${candidate}: ${error instanceof Error ? error.message : String(error)}`,
        );
      }
    }

    return null;
  }

  private cleanVisionString(value: unknown) {
    return `${value ?? ''}`.replace(/\s+/g, ' ').trim();
  }

  private normalizeHashtags(values: string[]) {
    return Array.from(
      new Set(
        values
          .map((item) => `${item ?? ''}`.trim())
          .filter((item) => item.length > 0)
          .map((item) => (item.startsWith('#') ? item : `#${item}`)),
      ),
    ).slice(0, 6);
  }

  private detectCommercialIntent(
    category: string,
    description: string,
    tags: string[],
    researchAngle: string,
  ) {
    const source = [category, description, ...tags, researchAngle].join(' ').toLowerCase();
    if (source.includes('camara') || source.includes('cámara') || source.includes('seguridad')) {
      return 'proteger hogares y negocios';
    }
    if (source.includes('porton') || source.includes('portón') || source.includes('motor')) {
      return 'automatizar accesos con seguridad';
    }
    if (source.includes('alarma')) {
      return 'recibir alertas y prevenir riesgos';
    }
    if (source.includes('red') || source.includes('wifi') || source.includes('internet')) {
      return 'mejorar conectividad y control';
    }
    return 'resolver necesidades tecnológicas con atención rápida';
  }

  private buildCampaignHeadline(category: string, commercialIntent: string, city: string) {
    const cleanCity = `${city}`.trim() || 'Higuey';
    const cleanCategory = `${category}`.trim() || 'soluciones Fulltech';
    if (commercialIntent.includes('proteger')) {
      return `Oferta especial en ${cleanCity}: protege tu propiedad`;
    }
    if (commercialIntent.includes('automatizar')) {
      return `Oferta especial en ${cleanCity}: automatiza tu entrada`;
    }
    if (commercialIntent.includes('alertas')) {
      return `Solo por hoy en ${cleanCity}: instala tu alarma`;
    }
    if (commercialIntent.includes('conectividad')) {
      return `Mejora tu red en ${cleanCity} con oferta especial`;
    }
    return `Oferta especial en ${cleanCity}: ${cleanCategory}`.substring(0, 80);
  }

  private buildCampaignSalesStrategy(commercialIntent: string, researchAngle: string, locationLabel: string) {
    const angle = `${researchAngle}`.trim();
    const shortAngle = angle.length > 150 ? `${angle.substring(0, 147).trim()}...` : angle;
    return [
      `captar clientes con una oferta local de alta urgencia en ${locationLabel}`,
      `resaltar ${commercialIntent}`,
      shortAngle ? `apoyado por la investigacion: ${shortAngle}` : '',
    ]
      .filter((item) => item.length > 0)
      .join('; ');
  }

  private buildCampaignPrimaryText(input: {
    category: string;
    commercialIntent: string;
    angle: string;
    salesStrategy: string;
    locationLabel: string;
    mediaDescription: string;
    mediaFileName: string;
  }) {
    const visualContext = this.firstText([input.mediaDescription, input.mediaFileName, input.category]);
    return [
      `Oferta especial solo por hoy en ${input.locationLabel}: aprovecha instalación profesional para ${input.commercialIntent}.`,
      `Servicio mostrado: ${visualContext.toLowerCase()}. Ideal para hogares y negocios que necesitan una solución confiable, rápida y bien instalada.`,
      `Agenda ya por WhatsApp, recibe orientación directa y asegura tu cotización antes de que termine la oferta.`,
    ].join(' ');
  }

  private buildCampaignDescription(
    category: string,
    commercialIntent: string,
    locationLabel: string,
    salesStrategy: string,
  ) {
    const cleanCategory = `${category}`.trim() || 'servicios Fulltech';
    const base = `${cleanCategory} para ${commercialIntent} en ${locationLabel}. Oferta especial, agenda hoy por WhatsApp.`;
    return `${base} ${salesStrategy ? 'Solo por hoy.' : ''}`.substring(0, 180).trim();
  }

  private buildCampaignHashtags(category: string, city: string, tags: string[]) {
    const base = [category, city, ...tags, 'Fulltech', 'WhatsApp']
      .map((item) => `${item ?? ''}`.trim())
      .filter((item) => item.length > 0)
      .map((item) => item.replace(/^#/, '').replace(/[^a-zA-Z0-9áéíóúÁÉÍÓÚñÑ]/g, ''))
      .filter((item) => item.length > 0)
      .map((item) => `#${item}`);
    return Array.from(new Set(base)).slice(0, 6);
  }

  async update(companyId: string, id: string, dto: UpdateMarketingCampaignDto, userId: string) {
    await this.ensure(companyId, id);

    const data: Prisma.MarketingAdCampaignUncheckedUpdateInput = {
      ...(dto.status ? { status: dto.status } : {}),
      ...(dto.phase ? { phase: dto.phase } : {}),
      ...(dto.headline !== undefined ? { headline: dto.headline?.trim() || null } : {}),
      ...(dto.primaryText !== undefined ? { primaryText: dto.primaryText?.trim() || null } : {}),
      ...(dto.description !== undefined ? { description: dto.description?.trim() || null } : {}),
      cta: 'WHATSAPP_MESSAGE',
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
    if (!`${campaign.whatsappPhone ?? ''}`.trim()) {
      throw new BadRequestException('Selecciona un WhatsApp destino antes de publicar.');
    }

    const audience = this.asRecord(campaign.finalAudienceJson) ??
      this.asRecord(campaign.recommendedAudienceJson) ??
      this.buildAudienceRecommendation('servicios', 'Higuey', 'La Altagracia');

    const targeting = this.mapAudienceToMetaTargeting(audience);

    try {
      const ids = await this.metaAds.createCampaignFlow({
        name: `${campaign.headline ?? 'Campaña'} ${new Date().toISOString().substring(0, 10)}`,
        objective: MarketingCampaignService.WHATSAPP_MESSAGES_OBJECTIVE,
        dailyBudget,
        totalBudget: campaign.totalBudget ? Number(campaign.totalBudget) : null,
        headline: campaign.headline ?? 'Campaña Fulltech',
        primaryText: campaign.primaryText ?? 'Conoce nuestra solución ahora mismo.',
        description: campaign.description,
        cta: 'WHATSAPP_MESSAGE',
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
        ageMax: 60,
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
