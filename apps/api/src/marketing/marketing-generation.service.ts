import { BadRequestException, ConflictException, Injectable, Logger, NotFoundException } from '@nestjs/common';
import { MarketingStoryType } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { MarketingImageGenerationService } from './marketing-image-generation.service';
import { MarketingMediaAssetService } from './marketing-media-asset.service';
import { MarketingMediaSelectorService } from './marketing-media-selector.service';
import { MarketingStorageService } from './marketing-storage.service';

type StoryTemplate = {
  title: string;
  shortText: string;
  longText: string;
  hashtags: string[];
  imagePrompt: string;
};

@Injectable()
export class MarketingGenerationService {
  private readonly logger = new Logger(MarketingGenerationService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly mediaSelector: MarketingMediaSelectorService,
    private readonly imageGeneration: MarketingImageGenerationService,
    private readonly mediaAssets: MarketingMediaAssetService,
    private readonly marketingStorage: MarketingStorageService,
  ) {}

  private readonly orderedTypes: MarketingStoryType[] = [
    MarketingStoryType.SALES,
    MarketingStoryType.TRUST,
    MarketingStoryType.EDUCATIONAL,
  ];

  private readonly localHooks = {
    SALES: ['No te compliques', 'Mira esto', 'Atencion negocio', 'Te conviene hoy'],
    TRUST: ['Asi es que se hace', 'Con respaldo de verdad', 'Trabajo limpio y serio', 'Aqui respondemos'],
    EDUCATIONAL: ['Dato rapido', 'Tip que si funciona', 'Aprende esto', 'Evita este error'],
  } as const;

  private readonly templates: Record<MarketingStoryType, StoryTemplate[]> = {
    SALES: [
      {
        title: 'Protege tu negocio hoy mismo',
        shortText: 'Camaras Full HD con instalacion profesional y soporte local.',
        longText:
          'Mejora la seguridad de tu hogar o negocio con camaras Full HD, monitoreo remoto y acompanamiento tecnico de FULLTECH. Cotiza hoy y recibe asesoria personalizada.',
        hashtags: ['#SeguridadInteligente', '#Camaras', '#FullTech'],
        imagePrompt: 'Camara de seguridad moderna instalada en negocio con iluminacion profesional',
      },
      {
        title: 'POS rapido para vender mas',
        shortText: 'Controla ventas, inventario y caja desde un solo sistema POS.',
        longText:
          'Digitaliza tu punto de venta con un POS confiable, facil de usar y adaptado a tu operacion. En FULLTECH te instalamos y capacitamos para empezar a vender mejor desde el primer dia.',
        hashtags: ['#POS', '#Ventas', '#Negocios'],
        imagePrompt: 'Terminal POS en mostrador de tienda con cliente pagando',
      },
      {
        title: 'Portones automatizados sin complicaciones',
        shortText: 'Mas seguridad y comodidad con instalacion certificada.',
        longText:
          'Automatiza el acceso a tu propiedad con motores de alto rendimiento para portones. Incluye instalacion profesional y soporte tecnico de respuesta rapida.',
        hashtags: ['#Portones', '#Automatizacion', '#Seguridad'],
        imagePrompt: 'Porton electrico moderno abriendose en residencia',
      },
    ],
    TRUST: [
      {
        title: 'Tu compra respaldada por garantia real',
        shortText: 'Trabajamos con garantia y seguimiento postventa.',
        longText:
          'En FULLTECH no solo vendemos: te acompanamos antes, durante y despues. Nuestro compromiso incluye garantia clara, instalacion profesional y soporte oportuno.',
        hashtags: ['#Garantia', '#Confianza', '#Servicio'],
        imagePrompt: 'Equipo tecnico uniformado atendiendo cliente satisfecho en tienda',
      },
      {
        title: 'Tienda fisica + atencion humana',
        shortText: 'Estamos cerca de ti para asesorarte con transparencia.',
        longText:
          'Contamos con tienda fisica y equipo especializado para ayudarte a elegir la mejor solucion segun tu necesidad y presupuesto, sin promesas vacias.',
        hashtags: ['#TiendaFisica', '#Asesoria', '#FullTech'],
        imagePrompt: 'Interior de tienda de tecnologia con asesores atendiendo',
      },
      {
        title: 'Instalacion profesional certificada',
        shortText: 'Tecnicos entrenados y procesos estandarizados.',
        longText:
          'Nuestro equipo tecnico trabaja con protocolos claros de instalacion para garantizar seguridad, rendimiento y orden en cada proyecto.',
        hashtags: ['#InstalacionProfesional', '#SoporteTecnico', '#Calidad'],
        imagePrompt: 'Tecnico instalando camara con herramientas profesionales',
      },
    ],
    EDUCATIONAL: [
      {
        title: '3 puntos clave para proteger tu negocio',
        shortText: 'Ubicacion, cobertura y respaldo: la base de una seguridad efectiva.',
        longText:
          'Antes de instalar camaras, define zonas criticas, evita puntos ciegos y asegura almacenamiento de evidencia. Una estrategia correcta reduce riesgos y mejora el control operativo.',
        hashtags: ['#ConsejosDeSeguridad', '#NegocioSeguro', '#Educativo'],
        imagePrompt: 'Plano simple de negocio con zonas de camaras marcadas',
      },
      {
        title: 'Por que un POS mejora tu rentabilidad',
        shortText: 'Menos errores, mejor inventario y reportes en tiempo real.',
        longText:
          'Un sistema POS te da trazabilidad de ventas, control de inventario y decisiones con datos reales. Esto evita perdidas y acelera el crecimiento de tu negocio.',
        hashtags: ['#GestionComercial', '#POS', '#Productividad'],
        imagePrompt: 'Dashboard de ventas en pantalla con grafico de crecimiento',
      },
      {
        title: 'Mantenimiento preventivo de camaras',
        shortText: 'Limpieza, ajustes y revision periodica para evitar fallos.',
        longText:
          'El mantenimiento preventivo evita interrupciones en momentos clave. Revisar enfoque, grabacion y energia de forma periodica aumenta la vida util del sistema.',
        hashtags: ['#Mantenimiento', '#CamarasSeguridad', '#Tips'],
        imagePrompt: 'Tecnico revisando camara de seguridad con checklist',
      },
    ],
  };

  async generateMissingStories(companyId: string, date: Date, userId?: string | null, researchId?: string | null) {
    let research: any = null;
    if (researchId) {
      research = await this.prisma.marketingResearch.findFirst({ where: { id: researchId, companyId } });
    }

    const researchConfig = await this.prisma.marketingResearchConfig.findUnique({
      where: { companyId },
    });

    const existing = await this.prisma.marketingDailyStory.findMany({
      where: { companyId, date },
      orderBy: { createdAt: 'asc' },
    });

    const usedAssetIds = new Set(
      existing
        .map((item) => (item as any).mediaAssetId as string | null)
        .filter((item): item is string => !!item),
    );

    const generated: string[] = [];

    for (const type of this.orderedTypes) {
      const current = existing.find((item) => item.type === type);
      if (!current) {
        const content = research ? this.pickResearchEnrichedTemplate(type, research) : this.pickTemplate(type);
        const visualData = await this.prepareQueuedVisualData({
          companyId,
          type,
          content,
          research,
          researchConfig,
          usedAssetIds,
        });
        await this.prisma.marketingDailyStory.create({
          data: {
            companyId,
            date,
            type,
            title: content.title,
            shortText: content.shortText,
            longText: content.longText,
            hashtags: content.hashtags,
            imagePrompt: visualData.imagePrompt,
            imageUrl: visualData.imageUrl,
            status: 'PENDING',
            generationAttempt: 1,
            researchId: researchId ?? null,
            mediaAssetId: visualData.mediaAssetId,
            visualConcept: visualData.visualConcept,
            designNotes: visualData.designNotes,
            platformFormat: 'STORY_9_16',
            imageStatus: 'QUEUED',
            generatedImageUrl: null,
            generatedImageProvider: null,
            imageGenerationMetadata: visualData.imageGenerationMetadata as any,
            usedResearchAngle: visualData.usedResearchAngle,
            usedOffer: visualData.usedOffer,
            usedCTA: visualData.usedCTA,
          },
        });
        if (visualData.mediaAssetId) {
          await this.mediaAssets.touchUsage(companyId, visualData.mediaAssetId);
          usedAssetIds.add(visualData.mediaAssetId);
          await this.logAssetUsage(companyId, visualData.mediaAssetId, userId ?? null, {
            type,
            date: this.toDateOnly(date),
          });
        }
        generated.push(type);
        continue;
      }

      if (current.status === 'PENDING' || current.status === 'APPROVED') {
        continue;
      }

      const content = research ? this.pickResearchEnrichedTemplate(type, research) : this.pickTemplate(type);
      const visualData = await this.prepareQueuedVisualData({
        companyId,
        type,
        content,
        research,
        researchConfig,
        usedAssetIds,
      });
      await this.prisma.marketingDailyStory.update({
        where: { id: current.id },
        data: {
          title: content.title,
          shortText: content.shortText,
          longText: content.longText,
          hashtags: content.hashtags,
          imagePrompt: visualData.imagePrompt,
          imageUrl: visualData.imageUrl,
          status: 'REGENERATED',
          generationAttempt: { increment: 1 },
          approvedAt: null,
          approvedByUserId: null,
          rejectedAt: null,
          researchId: researchId ?? (current as any).researchId ?? null,
          mediaAssetId: visualData.mediaAssetId,
          visualConcept: visualData.visualConcept,
          designNotes: visualData.designNotes,
          platformFormat: 'STORY_9_16',
          imageStatus: 'QUEUED',
          generatedImageUrl: null,
          generatedImageProvider: null,
          imageGenerationMetadata: visualData.imageGenerationMetadata as any,
          usedResearchAngle: visualData.usedResearchAngle,
          usedOffer: visualData.usedOffer,
          usedCTA: visualData.usedCTA,
        },
      });
      if (visualData.mediaAssetId) {
        await this.mediaAssets.touchUsage(companyId, visualData.mediaAssetId);
        usedAssetIds.add(visualData.mediaAssetId);
        await this.logAssetUsage(companyId, visualData.mediaAssetId, userId ?? null, {
          type,
          date: this.toDateOnly(date),
          mode: 'regenerated',
        });
      }
      generated.push(type);
    }

    if (generated.length > 0) {
      await this.prisma.marketingActivityLog.create({
        data: {
          companyId,
          action: 'MARKETING_STORIES_GENERATED',
          description: `Se generaron contenidos: ${generated.join(', ')}`,
          userId: userId ?? null,
          metadata: { date: this.toDateOnly(date), generatedTypes: generated, researchId: researchId ?? null },
        },
      });
    }

    return this.prisma.marketingDailyStory.findMany({
      where: { companyId, date },
      orderBy: { type: 'asc' },
      include: {
        approvedByUser: {
          select: { id: true, nombreCompleto: true },
        },
        mediaAsset: true,
      },
    });
  }

  async regenerateStory(companyId: string, storyId: string, userId: string) {
    const story = await this.prisma.marketingDailyStory.findFirst({
      where: { id: storyId, companyId },
    });
    if (!story) {
      throw new NotFoundException('Contenido no encontrado');
    }

    const research = story.researchId
      ? await this.prisma.marketingResearch.findFirst({
          where: { id: story.researchId, companyId },
        })
      : null;
    const researchConfig = await this.prisma.marketingResearchConfig.findUnique({
      where: { companyId },
    });
    const content = research ? this.pickResearchEnrichedTemplate(story.type, research) : this.pickTemplate(story.type);
    const visualData = await this.prepareQueuedVisualData({
      companyId,
      type: story.type,
      content,
      research,
      researchConfig,
      usedAssetIds: new Set<string>(story.mediaAssetId ? [story.mediaAssetId] : []),
    });
    const updated = await this.prisma.marketingDailyStory.update({
      where: { id: story.id },
      data: {
        title: content.title,
        shortText: content.shortText,
        longText: content.longText,
        hashtags: content.hashtags,
        imagePrompt: visualData.imagePrompt,
        imageUrl: visualData.imageUrl,
        status: 'REGENERATED',
        generationAttempt: { increment: 1 },
        approvedAt: null,
        approvedByUserId: null,
        rejectedAt: null,
        mediaAssetId: visualData.mediaAssetId,
        visualConcept: visualData.visualConcept,
        designNotes: visualData.designNotes,
        imageStatus: 'QUEUED',
        generatedImageUrl: null,
        generatedImageProvider: null,
        imageGenerationMetadata: visualData.imageGenerationMetadata as any,
        usedResearchAngle: visualData.usedResearchAngle,
        usedOffer: visualData.usedOffer,
        usedCTA: visualData.usedCTA,
      },
      include: {
        approvedByUser: {
          select: {
            id: true,
            nombreCompleto: true,
          },
        },
        mediaAsset: true,
      },
    });

    if (visualData.mediaAssetId) {
      await this.mediaAssets.touchUsage(companyId, visualData.mediaAssetId);
      await this.logAssetUsage(companyId, visualData.mediaAssetId, userId, {
        storyId: story.id,
        mode: 'single-regenerate',
      });
    }

    await this.prisma.marketingActivityLog.create({
      data: {
        companyId,
        action: 'MARKETING_STORY_REGENERATED',
        description: `Se regenero el contenido ${story.id} y la imagen quedo en cola`,
        userId,
        metadata: {
          storyId: story.id,
          type: story.type,
          generationAttempt: updated.generationAttempt,
        },
      },
    });

    return updated;
  }

  async queueStoryImageGeneration(companyId: string, storyId: string, userId: string, customPrompt?: string) {
    const story = await this.prisma.marketingDailyStory.findFirst({
      where: { id: storyId, companyId },
      include: { mediaAsset: true },
    });
    if (!story) {
      throw new NotFoundException('Contenido no encontrado');
    }

    const updated = await this.markStoryImageQueued(companyId, storyId, userId, customPrompt, {
      queuedAt: new Date().toISOString(),
      queueReason: 'manual-regenerate-image',
      previousStatus: story.imageStatus,
    });

    try {
      await this.prisma.marketingActivityLog.create({
        data: {
          companyId,
          action: 'MARKETING_STORY_IMAGE_REGENERATED',
          description: `Imagen puesta en cola para contenido ${storyId}`,
          userId,
          metadata: { storyId, mediaAssetId: updated.mediaAssetId ?? null },
        },
      });
    } catch (error) {
      const code = (error as { code?: string })?.code;
      if (code === 'P2003' || code === 'P2023') {
        this.logger.warn(
          `[marketing-image] activity-log skipped for story ${storyId}: userId invalido (${userId})`,
        );
      } else {
        throw error;
      }
    }

    return updated;
  }

  async markStoryImageQueued(
    companyId: string,
    storyId: string,
    userId: string,
    customPrompt?: string,
    metadata: Record<string, unknown> = {},
  ) {
    const story = await this.prisma.marketingDailyStory.findFirst({
      where: { id: storyId, companyId },
      include: {
        approvedByUser: { select: { id: true, nombreCompleto: true } },
        mediaAsset: true,
      },
    });
    if (!story) {
      throw new NotFoundException('Contenido no encontrado');
    }

    return this.prisma.marketingDailyStory.update({
      where: { id: storyId },
      data: {
        imagePrompt: customPrompt?.trim() || story.imagePrompt,
        imageStatus: 'QUEUED',
        generatedImageUrl: null,
        generatedImageProvider: null,
        imageGenerationMetadata: {
          ...(this.asObject(story.imageGenerationMetadata) ?? {}),
          ...metadata,
          queuedAt: new Date().toISOString(),
          queuedByUserId: userId,
          customPrompt: customPrompt?.trim() || null,
          lastError: null,
        } as any,
      },
      include: {
        approvedByUser: { select: { id: true, nombreCompleto: true } },
        mediaAsset: true,
      },
    });
  }

  async markStoryImageProcessing(companyId: string, storyId: string, attempt: number) {
    const story = await this.prisma.marketingDailyStory.findFirst({
      where: { id: storyId, companyId },
    });
    if (!story) {
      throw new NotFoundException('Contenido no encontrado');
    }

    await this.prisma.marketingDailyStory.update({
      where: { id: storyId },
      data: {
        imageStatus: 'PROCESSING',
        imageGenerationMetadata: {
          ...(this.asObject(story.imageGenerationMetadata) ?? {}),
          processingAt: new Date().toISOString(),
          processingAttempt: attempt,
        } as any,
      },
    });
  }

  async markStoryImageFailed(companyId: string, storyId: string, reason: string, attempt: number) {
    const story = await this.prisma.marketingDailyStory.findFirst({
      where: { id: storyId, companyId },
    });
    if (!story) {
      throw new NotFoundException('Contenido no encontrado');
    }

    await this.prisma.marketingDailyStory.update({
      where: { id: storyId },
      data: {
        imageStatus: 'FAILED',
        generatedImageUrl: null,
        generatedImageProvider: null,
        imageGenerationMetadata: {
          ...(this.asObject(story.imageGenerationMetadata) ?? {}),
          failedAt: new Date().toISOString(),
          processingAttempt: attempt,
          lastError: reason,
        } as any,
      },
    });
  }

  async processQueuedStoryImage(companyId: string, storyId: string, userId: string, customPrompt?: string) {
    const story = await this.prisma.marketingDailyStory.findFirst({
      where: { id: storyId, companyId },
      include: { mediaAsset: true },
    });
    if (!story) {
      throw new NotFoundException('Contenido no encontrado');
    }

    const researchConfig = await this.prisma.marketingResearchConfig.findUnique({ where: { companyId } });
    const usedResearchAngle = `${story.usedResearchAngle ?? ''}`.trim() || story.shortText;
    const usedOffer = `${story.usedOffer ?? ''}`.trim() || story.shortText;
    const usedCTA = `${story.usedCTA ?? ''}`.trim() || 'Cotiza por WhatsApp hoy';
    const visualConcept = `${story.visualConcept ?? ''}`.trim() || this.buildVisualConcept(story.type, usedResearchAngle, usedOffer);
    const designNotes = `${story.designNotes ?? ''}`.trim() || this.buildDesignNotes(story.type, usedCTA);
    const baseImageSourceUrl = `${story.mediaAsset?.fileUrl ?? story.imageUrl ?? ''}`.trim();
    const baseImage = baseImageSourceUrl
      ? await this.marketingStorage.saveBaseImageReference({
          companyId,
          storyType: this.storyTypeSlug(story.type),
          sourceUrl: baseImageSourceUrl,
        })
      : null;

    const generated = await this.imageGeneration.generateOrPrepare({
      companyName: researchConfig?.businessName ?? 'FULLTECH SRL',
      city: researchConfig?.city ?? 'Higüey',
      country: researchConfig?.country ?? 'República Dominicana',
      brandTone: researchConfig?.brandTone ?? 'tecnológico, limpio y profesional',
      brandColors: this.safeStringArray(researchConfig?.brandColors),
      title: story.title,
      cta: usedCTA,
      offer: usedOffer,
      visualConcept,
      designNotes,
      baseImageUrl: baseImageSourceUrl,
      imageCategory: story.mediaAsset?.category ?? this.galleryCategoryForType(story.type),
      serviceOrProduct:
        `${story.mediaAsset?.relatedService ?? ''}`.trim() ||
        usedOffer ||
        story.mediaAsset?.category ||
        this.galleryCategoryForType(story.type),
      usedResearchAngle,
      storyType: story.type as 'SALES' | 'TRUST' | 'EDUCATIONAL',
    });

    const savedGenerated = await this.marketingStorage.saveGeneratedImage({
      companyId,
      storyType: this.storyTypeSlug(story.type),
      sourceUrl: generated.generatedImageUrl || '',
    });
    const finalGeneratedUrl = `${savedGenerated?.url ?? ''}`.trim();
    if (!finalGeneratedUrl) {
      throw new BadRequestException('No se pudo persistir la imagen generada');
    }

    this.logger.log(`[marketing-image] saved generatedImageUrl storyId=${storyId} url=${finalGeneratedUrl}`);

    return this.prisma.marketingDailyStory.update({
      where: { id: storyId },
      data: {
        imagePrompt: customPrompt?.trim() || generated.prompt,
        imageUrl: `${baseImage?.url ?? story.imageUrl ?? ''}`.trim(),
        visualConcept: generated.visualConcept,
        designNotes: generated.designNotes,
        imageStatus: 'GENERATED',
        generatedImageUrl: finalGeneratedUrl,
        generatedImageProvider: generated.generatedImageProvider,
        imageGenerationMetadata: {
          ...generated.metadata,
          processedAt: new Date().toISOString(),
          baseImageSavedUrl: `${baseImage?.url ?? story.imageUrl ?? ''}`.trim() || null,
          generatedImageSavedUrl: finalGeneratedUrl,
          finalImageUrl: finalGeneratedUrl,
          lastError: null,
        } as any,
      },
      include: {
        approvedByUser: { select: { id: true, nombreCompleto: true } },
        mediaAsset: true,
      },
    }).then(async (updated) => {
      await this.prisma.marketingActivityLog.create({
        data: {
          companyId,
          action: 'MARKETING_STORY_IMAGE_GENERATED',
          description: `Imagen generada en background para contenido ${storyId}`,
          userId,
          metadata: { storyId, generatedImageUrl: finalGeneratedUrl },
        },
      });
      return updated;
    });
  }

  async regenerateStoryImageDirect(companyId: string, storyId: string, userId: string, customPrompt?: string) {
    const story = await this.prisma.marketingDailyStory.findFirst({
      where: { id: storyId, companyId },
    });
    if (!story) {
      throw new NotFoundException('Contenido no encontrado');
    }

    await this.markStoryImageProcessing(companyId, storyId, 1);
    try {
      const updated = await this.processQueuedStoryImage(companyId, storyId, userId, customPrompt);
      return updated;
    } catch (error) {
      const reason = error instanceof Error ? error.message : String(error);
      await this.markStoryImageFailed(companyId, storyId, reason, 1);
      throw error;
    }
  }

  async changeBaseImage(companyId: string, storyId: string, mediaAssetId: string, userId: string) {
    const story = await this.prisma.marketingDailyStory.findFirst({
      where: { id: storyId, companyId },
    });
    if (!story) {
      throw new NotFoundException('Contenido no encontrado');
    }
    const asset = await this.mediaAssets.ensure(companyId, mediaAssetId);
    const normalized = await this.marketingStorage.saveBaseImageReference({
      companyId,
      storyType: this.storyTypeSlug(story.type),
      sourceUrl: asset.fileUrl,
    });

    const updated = await this.prisma.marketingDailyStory.update({
      where: { id: storyId },
      data: {
        mediaAssetId: asset.id,
        imageUrl: normalized.url,
        generatedImageUrl: null,
        imageStatus: 'PENDING',
      },
      include: {
        approvedByUser: { select: { id: true, nombreCompleto: true } },
        mediaAsset: true,
      },
    });

    await this.mediaAssets.touchUsage(companyId, asset.id);
    await this.logAssetUsage(companyId, asset.id, userId, { storyId, mode: 'manual-change' });

    return updated;
  }

  private pickResearchEnrichedTemplate(type: MarketingStoryType, research: any): StoryTemplate {
    const hooks: string[] = Array.isArray(research.recommendedHooks) ? research.recommendedHooks : [];
    const offers: string[] = Array.isArray(research.recommendedOffers) ? research.recommendedOffers : [];
    const ctas: string[] = Array.isArray(research.recommendedCTAs) ? research.recommendedCTAs : [];
    const strong: string[] = Array.isArray(research.strongAngles) ? research.strongAngles : [];
    const products: string[] = Array.isArray(research.recommendedProducts) ? research.recommendedProducts : [];
    const base = this.pickTemplate(type);

    switch (type) {
      case MarketingStoryType.SALES: {
        const hook = hooks[0] ?? base.title;
        const offer = offers[0] ?? base.shortText;
        const cta = ctas[0] ?? 'Contáctanos hoy';
        const product = products[0] ?? 'nuestros servicios';
        const opportunity = (research.contentOpportunities ?? '').split('.')[0]?.trim() ?? '';
        return this.withDominicanVariation(type, {
          title: hook,
          shortText: offer,
          longText: `${opportunity || base.longText} ${cta}.`,
          hashtags: base.hashtags,
          imagePrompt: `${product} instalado profesionalmente, iluminación moderna, calidad premium`,
        });
      }
      case MarketingStoryType.TRUST: {
        const angle = strong[0] ?? base.shortText;
        const cta = ctas[1] ?? ctas[0] ?? 'Consúltanos sin compromiso';
        const commonOffer = (research.commonOffers ?? '').split('.')[0]?.trim() ?? '';
        return this.withDominicanVariation(type, {
          title: base.title,
          shortText: angle,
          longText: `${angle}. ${commonOffer ? commonOffer + '.' : ''} ${cta}.`.trim(),
          hashtags: base.hashtags,
          imagePrompt: base.imagePrompt,
        });
      }
      case MarketingStoryType.EDUCATIONAL: {
        const opportunity = (research.contentOpportunities ?? '').split('.').slice(0, 2).join('.').trim();
        const priceNote = (research.observedPriceRanges ?? '').split('.')[0]?.trim() ?? '';
        return this.withDominicanVariation(type, {
          title: base.title,
          shortText: priceNote ? `Referencia: ${priceNote}.` : base.shortText,
          longText: opportunity || base.longText,
          hashtags: base.hashtags,
          imagePrompt: base.imagePrompt,
        });
      }
    }
  }

  private pickTemplate(type: MarketingStoryType): StoryTemplate {
    const options = this.templates[type] ?? [];
    if (options.length == 0) {
      return this.withDominicanVariation(type, {
        title: 'Contenido del dia',
        shortText: 'Actualizacion de FULLTECH para nuestros clientes.',
        longText: 'Contenido temporal generado por plantilla.',
        hashtags: ['#FullTech'],
        imagePrompt: 'Diseno promocional tecnologico',
      });
    }
    const index = Math.floor(Math.random() * options.length);
    return this.withDominicanVariation(type, options[index]);
  }

  private withDominicanVariation(type: MarketingStoryType, input: StoryTemplate): StoryTemplate {
    const pool =
      type === MarketingStoryType.SALES
        ? this.localHooks.SALES
        : type === MarketingStoryType.TRUST
          ? this.localHooks.TRUST
          : this.localHooks.EDUCATIONAL;

    const hook = pool[Math.floor(Math.random() * pool.length)] || 'Mira esto';
    const head = this.ensurePunctuation(this.compact(input.title));
    const short = this.ensurePunctuation(this.compact(input.shortText));
    const long = this.compact(input.longText);

    const style = Math.floor(Math.random() * 3);
    if (style === 0) {
      return {
        ...input,
        title: `${hook}: ${head}`,
        shortText: short,
        longText: `${hook}. ${this.ensurePunctuation(long)}`,
      };
    }

    if (style === 1) {
      return {
        ...input,
        title: head,
        shortText: `${hook}. ${short}`,
        longText: this.ensurePunctuation(long),
      };
    }

    return {
      ...input,
      title: `${hook} - ${head}`,
      shortText: short,
      longText: `${this.ensurePunctuation(long)} ${this.ensurePunctuation('Escribenos y te orientamos sin vueltas')}`,
    };
  }

  private compact(value: string) {
    return `${value || ''}`.replace(/\s+/g, ' ').trim();
  }

  private ensurePunctuation(value: string) {
    const text = this.compact(value);
    if (!text) return text;
    const last = text[text.length - 1];
    if (['.', '!', '?', ':'].includes(last)) return text;
    return `${text}.`;
  }

  private async prepareVisualData(input: {
    companyId: string;
    type: MarketingStoryType;
    content: StoryTemplate;
    research: any | null;
    researchConfig: any | null;
    usedAssetIds: Set<string>;
    forceAssetId?: string;
    forcedPrompt?: string;
  }) {
    const hooks: string[] = this.safeStringArray(input.research?.recommendedHooks);
    const offers: string[] = this.safeStringArray(input.research?.recommendedOffers);
    const ctas: string[] = this.safeStringArray(input.research?.recommendedCTAs);
    const strong: string[] = this.safeStringArray(input.research?.strongAngles);
    const products: string[] = this.safeStringArray(input.research?.recommendedProducts);
    const mainServices: string[] = this.safeStringArray(input.researchConfig?.mainServices);

    const usedResearchAngle = strong[0] || hooks[0] || input.content.shortText;
    const usedOffer = offers[0] || input.content.shortText;
    const usedCTA = this.pickNaturalCta(ctas, input.researchConfig?.defaultCTA || 'Cotiza por WhatsApp hoy');
    const primaryService = products[0] || mainServices[0] || input.researchConfig?.priorityServices?.[0] || '';

    let selected = input.forceAssetId
      ? await this.prisma.marketingMediaAsset.findFirst({
          where: { id: input.forceAssetId, companyId: input.companyId, isActive: true },
        })
      : null;

    if (!selected) {
      selected = await this.mediaSelector.select({
        companyId: input.companyId,
        type: input.type,
        recommendedProduct: primaryService,
        recommendedService: primaryService,
        usedAssetIds: [...input.usedAssetIds],
      });
    }

    const visualConcept = this.buildVisualConcept(input.type, usedResearchAngle, primaryService);
    const designNotes = this.buildDesignNotes(input.type, usedCTA);

    let generated;
    try {
      generated = await this.imageGeneration.generateOrPrepare({
      companyName: input.researchConfig?.businessName ?? 'FULLTECH SRL',
      city: input.researchConfig?.city ?? 'Higüey',
      country: input.researchConfig?.country ?? 'República Dominicana',
      brandTone: input.researchConfig?.brandTone ?? 'tecnológico, limpio y profesional',
      brandColors: this.safeStringArray(input.researchConfig?.brandColors),
      title: input.content.title,
      cta: usedCTA,
      offer: usedOffer,
      visualConcept,
      designNotes,
      baseImageUrl: selected?.fileUrl ?? '',
      imageCategory: selected?.category ?? this.galleryCategoryForType(input.type),
      serviceOrProduct: primaryService || selected?.relatedService || selected?.category || this.galleryCategoryForType(input.type),
      usedResearchAngle,
      });
    } catch (error) {
      const reason = error instanceof Error ? error.message : String(error);
      generated = {
        imageStatus: 'FAILED' as const,
        generatedImageUrl: null,
        generatedImageProvider: '',
        prompt: input.forcedPrompt || input.content.imagePrompt,
        visualConcept,
        designNotes,
        metadata: {
          failedAt: new Date().toISOString(),
          reason,
        },
      };
    }

    const savedBase = selected
      ? await this.marketingStorage.saveBaseImageReference({
          companyId: input.companyId,
          storyType: this.storyTypeSlug(input.type),
          sourceUrl: selected.fileUrl,
        })
      : null;

    const savedGenerated = (generated.generatedImageUrl || '').trim()
      ? await this.marketingStorage.saveGeneratedImage({
          companyId: input.companyId,
          storyType: this.storyTypeSlug(input.type),
          sourceUrl: generated.generatedImageUrl || '',
        })
      : null;

    const baseImageUrl = (savedBase?.url || '').trim();
    const finalGeneratedUrl = (savedGenerated?.url || '').trim();
    const finalImageUrl = finalGeneratedUrl || baseImageUrl;

    return {
      mediaAssetId: selected?.id ?? null,
      imagePrompt: input.forcedPrompt || generated.prompt,
      // imageUrl keeps the selected base media from the gallery.
      imageUrl: baseImageUrl,
      visualConcept: generated.visualConcept,
      designNotes: generated.designNotes,
      imageStatus: generated.imageStatus,
      // generatedImageUrl is only the final generated output (if available).
      generatedImageUrl: finalGeneratedUrl || null,
      generatedImageProvider: generated.generatedImageProvider,
      imageGenerationMetadata: {
        ...generated.metadata,
        baseImageSavedUrl: baseImageUrl,
        generatedImageSavedUrl: finalGeneratedUrl || null,
        finalImageUrl: finalImageUrl || null,
      },
      usedResearchAngle,
      usedOffer,
      usedCTA,
    };
  }

  private async prepareQueuedVisualData(input: {
    companyId: string;
    type: MarketingStoryType;
    content: StoryTemplate;
    research: any | null;
    researchConfig: any | null;
    usedAssetIds: Set<string>;
    forceAssetId?: string;
    forcedPrompt?: string;
  }) {
    const hooks: string[] = this.safeStringArray(input.research?.recommendedHooks);
    const offers: string[] = this.safeStringArray(input.research?.recommendedOffers);
    const ctas: string[] = this.safeStringArray(input.research?.recommendedCTAs);
    const strong: string[] = this.safeStringArray(input.research?.strongAngles);
    const products: string[] = this.safeStringArray(input.research?.recommendedProducts);
    const mainServices: string[] = this.safeStringArray(input.researchConfig?.mainServices);

    const usedResearchAngle = strong[0] || hooks[0] || input.content.shortText;
    const usedOffer = offers[0] || input.content.shortText;
    const usedCTA = this.pickNaturalCta(ctas, input.researchConfig?.defaultCTA || 'Cotiza por WhatsApp hoy');
    const primaryService = products[0] || mainServices[0] || input.researchConfig?.priorityServices?.[0] || '';

    let selected = input.forceAssetId
      ? await this.prisma.marketingMediaAsset.findFirst({
          where: { id: input.forceAssetId, companyId: input.companyId, isActive: true },
        })
      : null;

    if (!selected) {
      selected = await this.mediaSelector.select({
        companyId: input.companyId,
        type: input.type,
        recommendedProduct: primaryService,
        recommendedService: primaryService,
        usedAssetIds: [...input.usedAssetIds],
      });
    }

    const visualConcept = this.buildVisualConcept(input.type, usedResearchAngle, primaryService);
    const designNotes = this.buildDesignNotes(input.type, usedCTA);
    const baseImageUrl = `${selected?.fileUrl ?? ''}`.trim();

    return {
      mediaAssetId: selected?.id ?? null,
      imagePrompt: input.forcedPrompt || input.content.imagePrompt,
      imageUrl: baseImageUrl,
      visualConcept,
      designNotes,
      imageGenerationMetadata: {
        queuedAt: new Date().toISOString(),
        queueReason: 'story-image-generation',
        baseImageSourceUrl: baseImageUrl || null,
        category: selected?.category ?? this.galleryCategoryForType(input.type),
        serviceOrProduct:
          primaryService || selected?.relatedService || selected?.category || this.galleryCategoryForType(input.type),
      },
      usedResearchAngle,
      usedOffer,
      usedCTA,
    };
  }

  private buildVisualConcept(type: MarketingStoryType, angle: string, service: string) {
    if (type === 'SALES') {
      return `Oferta directa enfocada en ${service || 'seguridad y automatización'} con énfasis en resultado inmediato (${angle}).`;
    }
    if (type === 'TRUST') {
      return `Prueba social y confianza de marca FULLTECH, destacando respaldo técnico y experiencia real (${angle}).`;
    }
    return `Contenido educativo visualmente limpio sobre ${service || 'soluciones tecnológicas'} con mensaje accionable (${angle}).`;
  }

  private buildDesignNotes(type: MarketingStoryType, cta: string) {
    if (type === 'SALES') {
      return `Composición vertical 9:16, texto principal grande, CTA visible: ${cta}, contraste alto y elementos tecnológicos.`;
    }
    if (type === 'TRUST') {
      return `Destacar personas/equipo o evidencia real, tono profesional, sello de confianza y CTA corto: ${cta}.`;
    }
    return `Distribución limpia con espacio para texto, estilo infografía ligera, cierre con CTA: ${cta}.`;
  }

  private galleryCategoryForType(type: MarketingStoryType) {
    if (type === 'SALES') return 'Promociones y productos';
    if (type === 'TRUST') return 'Instalaciones reales';
    return 'Tecnología general';
  }

  private storyTypeSlug(type: MarketingStoryType) {
    if (type === 'SALES') return 'venta';
    if (type === 'TRUST') return 'confianza';
    return 'educativo';
  }

  private assertReadyToSave(
    content: StoryTemplate,
    visual: {
      mediaAssetId: string | null;
      imageUrl: string;
      generatedImageUrl: string | null;
      usedCTA: string;
    },
  ) {
    const title = (content.title || '').trim();
    const shortText = (content.shortText || '').trim();
    const cta = (visual.usedCTA || '').trim();
    const image = (visual.imageUrl || visual.generatedImageUrl || '').trim();
    if (!title || !shortText || !cta) {
      throw new BadRequestException('No se puede guardar estado sin copy completo (headline, shortText y CTA).');
    }
    if (!image) {
      throw new BadRequestException(
        'No hay imagen publicitaria final válida para este estado.',
      );
    }
  }

  private pickNaturalCta(recommended: string[], fallback: string) {
    const options = [
      ...recommended,
      fallback,
      'Escribenos por WhatsApp y te orientamos rapido',
      'Llamanos hoy y te cotizamos sin compromiso',
      'Mira esto y consultanos ahora mismo',
    ]
      .map((item) => `${item || ''}`.trim())
      .filter((item) => item.length > 0);

    if (options.length === 0) {
      return 'Escribenos por WhatsApp y te orientamos rapido';
    }
    const index = Math.floor(Math.random() * options.length);
    return options[index];
  }

  private safeStringArray(value: unknown): string[] {
    if (!Array.isArray(value)) return [];
    return value.map((item) => `${item}`.trim()).filter((item) => item.length > 0);
  }

  private asObject(value: unknown): Record<string, unknown> | null {
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
      return null;
    }
    return value as Record<string, unknown>;
  }

  private async logAssetUsage(companyId: string, mediaAssetId: string, userId: string | null, metadata: Record<string, unknown>) {
    await this.prisma.marketingActivityLog.create({
      data: {
        companyId,
        action: 'MARKETING_MEDIA_ASSET_USED',
        description: `Asset de galería publicitaria utilizado: ${mediaAssetId}`,
        userId,
        metadata: {
          mediaAssetId,
          ...metadata,
        },
      },
    });
  }

  private toDateOnly(value: Date) {
    const year = value.getUTCFullYear();
    const month = `${value.getUTCMonth() + 1}`.padStart(2, '0');
    const day = `${value.getUTCDate()}`.padStart(2, '0');
    return `${year}-${month}-${day}`;
  }
}
