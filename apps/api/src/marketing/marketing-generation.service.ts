import { BadRequestException, ConflictException, Injectable, Logger, NotFoundException } from '@nestjs/common';
import { MarketingStoryType, ServiceEvidenceType } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { MarketingImageGenerationService } from './marketing-image-generation.service';
import { MarketingMediaAssetService } from './marketing-media-asset.service';
import { MarketingMediaSelectorService, SelectedMedia } from './marketing-media-selector.service';
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
    SALES: ['Solucion premium', 'Proteccion inteligente', 'Tecnologia que vende', 'Seguridad profesional'],
    TRUST: ['Respaldo profesional', 'Instalacion certificada', 'Experiencia real', 'Soporte confiable'],
    EDUCATIONAL: ['Guia practica', 'Recomendacion clave', 'Dato util', 'Mejor decision'],
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

  async generateMissingStories(
    companyId: string,
    date: Date,
    userId?: string | null,
    researchId?: string | null,
    selectedMediaAssetIds: string[] = [],
  ) {
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
    // Track base image URLs already in use today (handles catalog products that have id=null)
    const usedFileUrls = new Set(
      existing
        .map((item) => `${(item as any).imageUrl ?? ''}`.trim())
        .filter((url) => url.length > 0),
    );
    const selectedIds = this.normalizeIdList(selectedMediaAssetIds);

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
          usedFileUrls,
          preferredAssetIds: selectedIds,
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
            imageStatus: 'PENDING',
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
        if (visualData.selectedFileUrl) usedFileUrls.add(visualData.selectedFileUrl);
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
        usedFileUrls,
        preferredAssetIds: selectedIds,
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
          imageStatus: 'PENDING',
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
      if (visualData.selectedFileUrl) usedFileUrls.add(visualData.selectedFileUrl);
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
      usedFileUrls: new Set<string>(`${(story as any).imageUrl ?? ''}`.trim() ? [`${(story as any).imageUrl}`.trim()] : []),
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
        imageStatus: 'PENDING',
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

    try {
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
    } catch (err) {
      this.logger.warn(`[marketing] activity-log (STORY_REGENERATED) skipped: ${err instanceof Error ? err.message : String(err)}`);
    }

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

      if (story.imageStatus === 'PROCESSING') {
        throw new ConflictException('Ya se está generando el diseño. Espera a que termine antes de volver a intentar.');
      }

    await this.assertStoryUsesContentGallery(companyId, story);

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
      // Activity log is non-critical — never fail story generation because of it
      this.logger.warn(
        `[marketing-image] activity-log skipped for story ${storyId}: ${error instanceof Error ? error.message : String(error)}`,
      );
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

    await this.assertStoryUsesContentGallery(companyId, story);

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
          workflowStage: 'DESIGN_QUEUED',
          imageSelectionConfirmed: true,
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

    await this.assertStoryUsesContentGallery(companyId, story);

    const enrichedStory = await this.ensureStoryCopyAndHashtagsForDesign(companyId, story);

    const researchConfig = await this.prisma.marketingResearchConfig.findUnique({ where: { companyId } });
    const usedResearchAngle = `${enrichedStory.usedResearchAngle ?? ''}`.trim() || enrichedStory.shortText;
    const usedOffer = `${enrichedStory.usedOffer ?? ''}`.trim() || enrichedStory.shortText;
    const usedCTA = `${enrichedStory.usedCTA ?? ''}`.trim() || 'Cotiza por WhatsApp hoy';
    const visualConcept = `${enrichedStory.visualConcept ?? ''}`.trim() || this.buildVisualConcept(enrichedStory.type, usedResearchAngle, usedOffer);
    const designNotes = `${enrichedStory.designNotes ?? ''}`.trim() || this.buildDesignNotes(enrichedStory.type, usedCTA);
    const baseImageSourceUrl = `${enrichedStory.mediaAsset?.fileUrl ?? enrichedStory.imageUrl ?? ''}`.trim();
    const baseImage = baseImageSourceUrl
      ? await this.marketingStorage.saveBaseImageReference({
          companyId,
          storyType: this.storyTypeSlug(enrichedStory.type),
          sourceUrl: baseImageSourceUrl,
        })
      : null;

    const serviceOrProduct =
      `${enrichedStory.mediaAsset?.relatedService ?? ''}`.trim() ||
      usedOffer ||
      enrichedStory.mediaAsset?.category ||
      this.galleryCategoryForType(enrichedStory.type);
    const brandColors = this.safeStringArray(researchConfig?.brandColors);

    let generated;
    let providerError: string | null = null;
    try {
      generated = await this.imageGeneration.generateOrPrepare({
        companyName: researchConfig?.businessName ?? 'FULLTECH SRL',
        city: researchConfig?.city ?? 'Higüey',
        country: researchConfig?.country ?? 'República Dominicana',
        brandTone: researchConfig?.brandTone ?? 'tecnológico, limpio y profesional',
        brandColors,
        title: enrichedStory.title,
        cta: usedCTA,
        offer: usedOffer,
        visualConcept,
        designNotes,
        baseImageUrl: baseImageSourceUrl,
        imageCategory: enrichedStory.mediaAsset?.category ?? this.galleryCategoryForType(enrichedStory.type),
        serviceOrProduct,
        usedResearchAngle,
        storyType: enrichedStory.type as 'SALES' | 'TRUST' | 'EDUCATIONAL',
      });
    } catch (error) {
      providerError = error instanceof Error ? error.message : String(error);
        this.logger.error(`[marketing-image] provider failed storyId=${storyId}: ${providerError}`);
        throw new BadRequestException(providerError || 'Error desconocido al generar imagen con IA.');
    }

    const generatedImageSourceUrl = `${generated.generatedImageUrl ?? ''}`.trim();
    if (!generatedImageSourceUrl) {
        throw new BadRequestException('No se pudo generar una imagen final válida. El proveedor de IA no devolvió imagen.');
    }

    const savedGenerated = await this.marketingStorage.saveGeneratedImage({
      companyId,
      storyType: this.storyTypeSlug(enrichedStory.type),
      sourceUrl: generatedImageSourceUrl,
    });
    const finalGeneratedUrl = `${savedGenerated?.url ?? ''}`.trim();
    if (!finalGeneratedUrl) {
      throw new BadRequestException('No se pudo persistir la imagen generada');
    }

    // Validate generated image quality and format
      // Skip heavy validation for data-URLs (already normalized by sharp in provider);
      // only validate when we have a real HTTP URL (after upload to R2).
      if (finalGeneratedUrl.startsWith('http://') || finalGeneratedUrl.startsWith('https://')) {
        const validation = await this.imageGeneration.validateGeneratedImage(
          finalGeneratedUrl,
          '9:16',
          `${baseImage?.url ?? baseImageSourceUrl}`.trim(),
        );
        if (!validation.valid) {
          this.logger.warn(`[marketing-image] validation failed storyId=${storyId}: ${validation.reason}`);
          await this.markStoryImageFailed(companyId, storyId, `Validacion de imagen fallida: ${validation.reason || 'Imagen invalida'}`, 1);
          throw new BadRequestException(`La imagen generada no cumple los estándares de calidad: ${validation.reason || 'Imagen inválida o dañada'}`);
        }
      }

    this.logger.log(`[marketing-image] saved and validated generatedImageUrl storyId=${storyId} url=${finalGeneratedUrl}`);
      this.logger.log(`[marketing-image] uploaded final url=${finalGeneratedUrl}`);

    return this.prisma.marketingDailyStory.update({
      where: { id: storyId },
      data: {
        title: enrichedStory.title,
        shortText: enrichedStory.shortText,
        longText: enrichedStory.longText,
        hashtags: enrichedStory.hashtags,
        usedOffer,
        usedCTA,
        imagePrompt: customPrompt?.trim() || generated.prompt,
        imageUrl: `${baseImage?.url ?? enrichedStory.imageUrl ?? ''}`.trim(),
        visualConcept: generated.visualConcept,
        designNotes: generated.designNotes,
        imageStatus: 'GENERATED',
        generatedImageUrl: finalGeneratedUrl,
        generatedImageProvider: generated.generatedImageProvider,
        imageGenerationMetadata: {
          ...generated.metadata,
          processedAt: new Date().toISOString(),
          compositionMode: 'provider-image-edit',
          providerError,
          baseImageSavedUrl: `${baseImage?.url ?? enrichedStory.imageUrl ?? ''}`.trim() || null,
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
      try {
        await this.prisma.marketingActivityLog.create({
          data: {
            companyId,
            action: 'MARKETING_STORY_IMAGE_GENERATED',
            description: `Imagen generada en background para contenido ${storyId}`,
            userId,
            metadata: { storyId, generatedImageUrl: finalGeneratedUrl },
          },
        });
      } catch (error) {
        // Activity log is non-critical — never fail the story generation because of it
        this.logger.warn(
          `[marketing-image] activity-log skipped for story ${storyId}: ${error instanceof Error ? error.message : String(error)}`,
        );
      }
      return updated;
    });
  }

  private async ensureStoryCopyAndHashtagsForDesign(companyId: string, story: any) {
    const research = story.researchId
      ? await this.prisma.marketingResearch.findFirst({
          where: { id: story.researchId, companyId },
        })
      : null;
    const researchConfig = await this.prisma.marketingResearchConfig.findUnique({
      where: { companyId },
    });

    const template = research
      ? this.pickResearchEnrichedTemplate(story.type, research)
      : this.pickTemplate(story.type);
    const recommendedCtas = this.safeStringArray(research?.recommendedCTAs);
    const fallbackCta =
      `${researchConfig?.defaultCTA ?? ''}`.trim() ||
      'Cotiza por WhatsApp hoy';

    const title = this.compact(`${story.title ?? ''}`) || template.title;
    const shortText = this.compact(`${story.shortText ?? ''}`) || template.shortText;
    const longText = this.ensurePunctuation(
      this.compact(`${story.longText ?? ''}`) || template.longText,
    );
    const usedOffer = this.compact(`${story.usedOffer ?? ''}`) || shortText;
    const usedCTA =
      this.compact(`${story.usedCTA ?? ''}`) ||
      this.pickNaturalCta(recommendedCtas, fallbackCta);
    const usedResearchAngle =
      this.compact(`${story.usedResearchAngle ?? ''}`) || shortText;
    const existingHashtags = this.safeStringArray(story.hashtags);
    const hashtags = this.buildBestHashtags({
      type: story.type,
      existing: existingHashtags,
      template: existingHashtags.length >= 3 ? [] : template.hashtags,
      serviceHint:
        `${story.mediaAsset?.relatedService ?? ''}`.trim() ||
        `${story.usedOffer ?? ''}`.trim() ||
        `${researchConfig?.mainServices?.[0] ?? ''}`.trim(),
      categoryHint: `${story.mediaAsset?.category ?? ''}`.trim(),
      cityHint: `${researchConfig?.city ?? ''}`.trim(),
    });

    const payload = {
      title,
      shortText,
      longText,
      hashtags,
      imagePrompt: this.compact(`${story.imagePrompt ?? ''}`) || template.imagePrompt,
      usedOffer,
      usedCTA,
      usedResearchAngle,
    };

    const changed =
      payload.title !== `${story.title ?? ''}` ||
      payload.shortText !== `${story.shortText ?? ''}` ||
      payload.longText !== `${story.longText ?? ''}` ||
      payload.imagePrompt !== `${story.imagePrompt ?? ''}` ||
      payload.usedOffer !== `${story.usedOffer ?? ''}` ||
      payload.usedCTA !== `${story.usedCTA ?? ''}` ||
      payload.usedResearchAngle !== `${story.usedResearchAngle ?? ''}` ||
      !this.sameStringList(payload.hashtags, this.safeStringArray(story.hashtags));

    if (!changed) {
      return story;
    }

    return this.prisma.marketingDailyStory.update({
      where: { id: story.id },
      data: payload,
      include: {
        approvedByUser: { select: { id: true, nombreCompleto: true } },
        mediaAsset: true,
      },
    });
  }

  private buildBestHashtags(input: {
    type: MarketingStoryType;
    existing: string[];
    template: string[];
    serviceHint: string;
    categoryHint: string;
    cityHint: string;
  }) {
    const normalized = [
      ...input.existing,
      ...input.template,
      '#FullTech',
      '#PublicidadDigital',
      input.type === 'SALES'
        ? '#Ventas'
        : input.type === 'TRUST'
        ? '#Confianza'
        : '#Educativo',
    ]
      .map((tag) => this.normalizeHashtag(tag))
      .filter((tag): tag is string => tag != null);

    const signal = `${input.serviceHint} ${input.categoryHint}`.toLowerCase();
    if (signal.includes('camar')) normalized.push('#CamarasDeSeguridad');
    if (signal.includes('porton')) normalized.push('#PortonesAutomaticos');
    if (signal.includes('pos') || signal.includes('punto de venta')) normalized.push('#SistemaPOS');
    if (signal.includes('alarm')) normalized.push('#Alarmas');
    if (signal.includes('instal')) normalized.push('#InstalacionProfesional');

    const cityTag = this.normalizeHashtag(`#${input.cityHint.replaceAll(' ', '')}`);
    if (cityTag != null && cityTag.length > 2) {
      normalized.push(cityTag);
    }

    return [...new Set(normalized)].slice(0, 8);
  }

  private normalizeHashtag(raw: string) {
    const cleaned = `${raw}`.trim();
    if (!cleaned) return null;
    const noHash = cleaned.replaceAll('#', '');
    if (!noHash.trim()) return null;
    const normalized = noHash
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/[^a-zA-Z0-9]+/g, ' ')
      .trim()
      .split(/\s+/)
      .map((part) =>
        part.length === 0
          ? part
          : `${part[0].toUpperCase()}${part.substring(1).toLowerCase()}`,
      )
      .join('');
    if (!normalized) return null;
    return `#${normalized}`;
  }

  private sameStringList(a: string[], b: string[]) {
    if (a.length !== b.length) return false;
    for (let i = 0; i < a.length; i += 1) {
      if (a[i] !== b[i]) return false;
    }
    return true;
  }

  private async assertStoryUsesContentGallery(
    companyId: string,
    story: { mediaAssetId?: string | null },
  ) {
    const mediaAssetId = `${story.mediaAssetId ?? ''}`.trim();
    if (!mediaAssetId) {
      throw new ConflictException(
        'Generar diseño requiere una imagen seleccionada desde Publicidad > Galería de contenido.',
      );
    }

    const exists = await this.prisma.marketingMediaAsset.findFirst({
      where: {
        id: mediaAssetId,
        companyId,
      },
      select: { id: true },
    });
    if (!exists) {
      throw new ConflictException(
        'La imagen seleccionada no pertenece a la Galería de contenido de Publicidad.',
      );
    }
  }

  async regenerateStoryImageDirect(companyId: string, storyId: string, userId: string, customPrompt?: string) {
    const story = await this.prisma.marketingDailyStory.findFirst({
      where: { id: storyId, companyId },
    });
    if (!story) {
      throw new NotFoundException('Contenido no encontrado');
    }

    await this.assertStoryUsesContentGallery(companyId, story);

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
    const asset = await this.ensureSelectableAsset(companyId, mediaAssetId);
    const normalized = await this.marketingStorage.saveBaseImageReference({
      companyId,
      storyType: this.storyTypeSlug(story.type),
      sourceUrl: asset.fileUrl,
    });

    const nowIso = new Date().toISOString();
    const autoPrompt = this.buildAutoPromptFromSelectedBaseImage(story, asset);

    const updated = await this.prisma.marketingDailyStory.update({
      where: { id: storyId },
      data: {
        mediaAssetId: asset.id,
        imageUrl: normalized.url,
        imagePrompt: autoPrompt,
        generatedImageUrl: null,
        imageStatus: 'PENDING',
        imageGenerationMetadata: {
          ...(this.asObject(story.imageGenerationMetadata) ?? {}),
          workflowStage: 'BASE_IMAGE_AUTO_READY',
          imageSelectionConfirmed: true,
          confirmedAt: nowIso,
          confirmedByUserId: userId,
          selectedAt: nowIso,
          selectedByUserId: userId,
          contentGalleryItemId: asset.id,
          imageUrl: normalized.url,
          baseImageSourceUrl: asset.fileUrl,
          autoPromptAt: nowIso,
          autoPromptSource: 'selected-base-image-and-research',
          selectedMediaAssetId: asset.id,
          thumbnailUrl: asset.thumbnailUrl ?? null,
          categoria: asset.category,
          descripcion: asset.description ?? null,
          tags: Array.isArray(asset.tags) ? asset.tags : [],
          origen: `${(asset as any).sourceType ?? ''}`.trim() || 'content-gallery',
          selectedMediaCategory: asset.category,
        } as any,
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

  private async ensureSelectableAsset(companyId: string, mediaAssetId: string) {
    try {
      return await this.mediaAssets.ensure(companyId, mediaAssetId);
    } catch (error) {
      if (!(error instanceof NotFoundException)) {
        throw error;
      }
    }

    const evidence = await this.prisma.serviceEvidence.findFirst({
      where: {
        id: mediaAssetId,
        forPublicidad: true,
        type: {
          in: [
            ServiceEvidenceType.REFERENCIA_IMAGEN,
            ServiceEvidenceType.EVIDENCIA_IMAGEN,
            ServiceEvidenceType.REFERENCIA_VIDEO,
            ServiceEvidenceType.EVIDENCIA_VIDEO,
          ],
        },
      },
      include: {
        serviceOrder: {
          select: {
            serviceType: true,
            status: true,
          },
        },
      },
    });

    if (evidence) {
      const sourceUrl = `${evidence.content ?? ''}`.trim();
      if (!sourceUrl) {
        throw new ConflictException('La imagen seleccionada no tiene URL válida.');
      }

      const existingByUrl = await this.prisma.marketingMediaAsset.findFirst({
        where: {
          companyId,
          fileUrl: sourceUrl,
        },
      });
      if (existingByUrl) {
        return existingByUrl;
      }

      const isVideo =
        evidence.type === ServiceEvidenceType.REFERENCIA_VIDEO ||
        evidence.type === ServiceEvidenceType.EVIDENCIA_VIDEO;
      return this.prisma.marketingMediaAsset.create({
        data: {
          companyId,
          fileUrl: sourceUrl,
          thumbnailUrl: null,
          fileName: this.extractFileName(sourceUrl, evidence.id),
          mimeType: this.inferMimeType(sourceUrl, isVideo),
          category: isVideo ? 'Galería media (video)' : 'Galería media (imagen)',
          relatedService: `${evidence.serviceOrder?.serviceType ?? ''}`.trim() || 'Galería media',
          tags: [
            'galeria-media',
            'for-publicidad',
            'evidencia-tecnica',
            isVideo ? 'video' : 'imagen',
          ],
          description: null,
          isActive: true,
          isFeatured: false,
        },
      });
    }

    const ownImage = await this.prisma.publicidadImage.findUnique({
      where: { id: mediaAssetId },
    });
    if (ownImage) {
      const sourceUrl = `${ownImage.url ?? ''}`.trim();
      if (!sourceUrl) {
        throw new ConflictException('La imagen seleccionada no tiene URL válida.');
      }

      const existingByUrl = await this.prisma.marketingMediaAsset.findFirst({
        where: {
          companyId,
          fileUrl: sourceUrl,
        },
      });
      if (existingByUrl) {
        return existingByUrl;
      }

      return this.prisma.marketingMediaAsset.create({
        data: {
          companyId,
          fileUrl: sourceUrl,
          thumbnailUrl: null,
          fileName: this.extractFileName(sourceUrl, ownImage.id),
          mimeType: this.inferMimeType(sourceUrl, false),
          category: 'Galería publicidad',
          relatedService: null,
          tags: ['galeria-publicidad', 'subida-directamente', 'imagen'],
          description: ownImage.caption ?? null,
          isActive: true,
          isFeatured: false,
        },
      });
    }

    throw new NotFoundException('Asset de publicidad no encontrado');
  }

  private extractFileName(url: string, fallbackId: string) {
    const parsed = this.safeParseUrl(url);
    const path = (parsed?.pathname ?? '').trim();
    if (!path) return `content-${fallbackId}.jpg`;
    const parts = path.split('/').filter((part) => part.trim().length > 0);
    const last = (parts[parts.length - 1] ?? '').trim();
    if (!last) return `content-${fallbackId}.jpg`;
    return last;
  }

  private inferMimeType(url: string, isVideo: boolean) {
    const lower = `${url}`.toLowerCase();
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.jpeg') || lower.endsWith('.jpg')) return 'image/jpeg';
    return isVideo ? 'video/mp4' : 'image/jpeg';
  }

  private safeParseUrl(url: string) {
    try {
      return new URL(url);
    } catch {
      return null;
    }
  }

  async confirmBaseImageSelection(companyId: string, storyId: string, userId: string) {
    const story = await this.prisma.marketingDailyStory.findFirst({
      where: { id: storyId, companyId },
    });
    if (!story) {
      throw new NotFoundException('Contenido no encontrado');
    }

    const baseImageUrl = `${story.imageUrl ?? ''}`.trim();
    if (!baseImageUrl) {
      throw new ConflictException('No hay imagen base seleccionada para confirmar.');
    }

    return this.prisma.marketingDailyStory.update({
      where: { id: story.id },
      data: {
        imageStatus: 'PENDING',
        imageGenerationMetadata: {
          ...(this.asObject(story.imageGenerationMetadata) ?? {}),
          workflowStage: 'BASE_IMAGE_CONFIRMED',
          imageSelectionConfirmed: true,
          confirmedAt: new Date().toISOString(),
          confirmedByUserId: userId,
          lastError: null,
        } as any,
      },
      include: {
        approvedByUser: { select: { id: true, nombreCompleto: true } },
        mediaAsset: true,
      },
    });
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
    const head = this.ensurePunctuation(this.compact(input.title));
    const short = this.ensurePunctuation(this.compact(input.shortText));
    const long = this.compact(input.longText);
    return {
      ...input,
      title: this.compact(head.replace(/[.!?]+$/, '')),
      shortText: short,
      longText: this.ensurePunctuation(long),
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
    const recommendedServiceHint = products[0] || mainServices[0] || input.researchConfig?.priorityServices?.[0] || '';

    let selected: SelectedMedia | null = null;
    if (input.forceAssetId) {
      const asset = await this.prisma.marketingMediaAsset.findFirst({
        where: { id: input.forceAssetId, companyId: input.companyId, isActive: true },
      });
      if (asset) selected = { ...asset, sourceType: 'gallery' as const };
    }

    if (!selected) {
      selected = await this.mediaSelector.select({
        companyId: input.companyId,
        type: input.type,
        recommendedProduct: recommendedServiceHint,
        recommendedService: recommendedServiceHint,
        usedAssetIds: [...input.usedAssetIds],
        imagePrompt: input.content.imagePrompt,
        copyText: input.content.shortText,
      });
    }

    const primaryService = selected?.relatedService || recommendedServiceHint || input.content.shortText;
    const usedResearchAngle = strong[0] || hooks[0] || primaryService || input.content.shortText;
    const usedOffer = offers[0] || primaryService || input.content.shortText;
    const usedCTA = this.pickNaturalCta(ctas, input.researchConfig?.defaultCTA || 'Cotiza por WhatsApp hoy');

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
      storyType: input.type as 'SALES' | 'TRUST' | 'EDUCATIONAL',
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

  private buildAutoPromptFromSelectedBaseImage(
    story: {
      type: MarketingStoryType;
      shortText?: string | null;
      usedResearchAngle?: string | null;
      usedOffer?: string | null;
      usedCTA?: string | null;
      imagePrompt?: string | null;
    },
    asset: {
      category?: string | null;
      relatedService?: string | null;
      description?: string | null;
      tags?: unknown;
    },
  ) {
    const category = this.compact(`${asset.category ?? ''}`);
    const relatedService = this.compact(`${asset.relatedService ?? ''}`);
    const description = this.compact(`${asset.description ?? ''}`);
    const tags = Array.isArray(asset.tags)
      ? asset.tags
          .map((item) => this.compact(`${item ?? ''}`))
          .filter((item) => item.length > 0)
          .slice(0, 6)
          .join(', ')
      : '';

    const angle =
      this.compact(`${story.usedResearchAngle ?? ''}`) ||
      this.compact(`${story.shortText ?? ''}`) ||
      'beneficio real y confianza de cliente';
    const offer =
      this.compact(`${story.usedOffer ?? ''}`) ||
      this.compact(`${story.shortText ?? ''}`) ||
      'servicio profesional de FULLTECH';
    const cta = this.compact(`${story.usedCTA ?? ''}`) || 'Escribenos por WhatsApp hoy';

    const serviceHint = relatedService || category || 'servicio técnico';
    const visualConcept = this.buildVisualConcept(story.type, angle, serviceHint);
    const designNotes = this.buildDesignNotes(story.type, cta);

    const contextParts = [
      relatedService,
      category,
      description,
      tags,
    ].filter((item) => item.length > 0);

    const fallbackPrompt = this.compact(`${story.imagePrompt ?? ''}`);
    const autoPrompt = this.compact(
      [
        `Usa la imagen base seleccionada como referencia principal.`,
        `Producto/servicio visible: ${serviceHint}.`,
        `Ángulo de investigación: ${angle}.`,
        `Oferta clave: ${offer}.`,
        contextParts.length > 0
          ? `Contexto visual detectado: ${contextParts.join(' | ')}.`
          : '',
        `Regla crítica: conservar el producto real, sin cambiar su identidad ni proporciones.`,
        visualConcept,
        designNotes,
      ].join(' '),
    );

    return autoPrompt || fallbackPrompt || 'Diseño publicitario vertical 9:16 con enfoque comercial premium.';
  }

  private async prepareQueuedVisualData(input: {
    companyId: string;
    type: MarketingStoryType;
    content: StoryTemplate;
    research: any | null;
    researchConfig: any | null;
    usedAssetIds: Set<string>;
    usedFileUrls: Set<string>;
    preferredAssetIds?: string[];
    forceAssetId?: string;
    forcedPrompt?: string;
  }) {
    const hooks: string[] = this.safeStringArray(input.research?.recommendedHooks);
    const offers: string[] = this.safeStringArray(input.research?.recommendedOffers);
    const ctas: string[] = this.safeStringArray(input.research?.recommendedCTAs);
    const strong: string[] = this.safeStringArray(input.research?.strongAngles);
    const products: string[] = this.safeStringArray(input.research?.recommendedProducts);
    const mainServices: string[] = this.safeStringArray(input.researchConfig?.mainServices);
    const recommendedServiceHint = products[0] || mainServices[0] || input.researchConfig?.priorityServices?.[0] || '';

    let selected: SelectedMedia | null = null;
    if (input.forceAssetId) {
      const asset = await this.prisma.marketingMediaAsset.findFirst({
        where: { id: input.forceAssetId, companyId: input.companyId, isActive: true },
      });
      if (asset) selected = { ...asset, sourceType: 'gallery' as const };
    }

    if (!selected) {
      selected = await this.mediaSelector.select({
        companyId: input.companyId,
        type: input.type,
        recommendedProduct: recommendedServiceHint,
        recommendedService: recommendedServiceHint,
        usedAssetIds: [...input.usedAssetIds],
        usedFileUrls: [...input.usedFileUrls],
        preferredAssetIds: input.preferredAssetIds ?? [],
        imagePrompt: input.content.imagePrompt,
        copyText: input.content.shortText,
      });
    }

    const primaryService = selected?.relatedService || recommendedServiceHint || input.content.shortText;
    const usedResearchAngle = strong[0] || hooks[0] || primaryService || input.content.shortText;
    const usedOffer = offers[0] || primaryService || input.content.shortText;
    const usedCTA = this.pickNaturalCta(ctas, input.researchConfig?.defaultCTA || 'Cotiza por WhatsApp hoy');

    const visualConcept = this.buildVisualConcept(input.type, usedResearchAngle, primaryService);
    const designNotes = this.buildDesignNotes(input.type, usedCTA);
    const baseImageUrl = `${selected?.fileUrl ?? ''}`.trim();
    const selectedReferenceSummary = this.buildReferenceSummary(selected, input.preferredAssetIds ?? []);

    return {
      mediaAssetId: selected?.id ?? null,
      selectedFileUrl: baseImageUrl,
      selectedReferenceSummary,
      imagePrompt: input.forcedPrompt || input.content.imagePrompt,
      imageUrl: baseImageUrl,
      visualConcept,
      designNotes,
      imageGenerationMetadata: {
        workflowStage: 'BASE_IMAGE_AUTO_READY',
        imageSelectionConfirmed: true,
        selectedAt: new Date().toISOString(),
        confirmedAt: new Date().toISOString(),
        queueReason: 'auto-ready-base-image',
        baseImageSourceUrl: baseImageUrl || null,
        category: selected?.category ?? this.galleryCategoryForType(input.type),
        serviceOrProduct:
          primaryService || selected?.relatedService || selected?.category || this.galleryCategoryForType(input.type),
        selectedReferenceSummary,
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

  private buildReferenceSummary(selected: SelectedMedia | null, preferredAssetIds: string[]) {
    const preferred = this.takeUnique(preferredAssetIds, 3);
    const selectedLabel = selected?.category?.trim() || selected?.relatedService?.trim() || 'Referencia comercial';
    return [
      `Referencia principal: ${selectedLabel}`,
      preferred.length > 0 ? `Referencias elegidas: ${preferred.join(', ')}` : 'Referencias elegidas: ninguna adicional',
      'Analisis visual: conservar producto original, mejorar composicion, luz y jerarquia comercial.',
    ].join(' | ');
  }

  private normalizeIdList(ids: string[]) {
    return this.takeUnique(ids.map((id) => id.trim()).filter((id) => id.length > 0), 3);
  }

  private takeUnique(values: string[], max: number): string[] {
    const cleaned = values
      .map((item) => item.trim())
      .filter((item) => item.length > 0);
    return [...new Set(cleaned)].slice(0, max);
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

  private isImageSelectionConfirmed(story: { imageGenerationMetadata?: unknown }) {
    const metadata = this.asObject(story.imageGenerationMetadata) ?? {};
    return metadata.imageSelectionConfirmed === true;
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

  /**
   * Analyzes the manually uploaded final design media (image/video) using OpenAI
   * and regenerates ONLY the copy fields (title, shortText, hashtags, usedCTA).
   * Does NOT touch imageUrl, generatedImageUrl, imageStatus or the design flow.
   */
  async regenerateCopyFromDesignImage(companyId: string, storyId: string, userId: string) {
    const story = await this.prisma.marketingDailyStory.findFirst({
      where: { id: storyId, companyId },
      include: {
        mediaAsset: {
          select: {
            mimeType: true,
          },
        },
      },
    });
    if (!story) throw new NotFoundException('Contenido no encontrado');

    const designUrl = (`${(story as any).imageUrl ?? ''}`.trim());
    if (!designUrl) {
      throw new BadRequestException(
        'Este contenido no tiene diseño final subido. Sube el diseño primero.',
      );
    }
    const mediaMimeType = `${(story as any).mediaAsset?.mimeType ?? ''}`
      .trim()
      .toLowerCase();
    const isVideoDesign =
      mediaMimeType.startsWith('video/') ||
      this.isVideoUrl(designUrl) ||
      (await this.isRemoteVideoByContentType(designUrl));

    // Retrieve OpenAI config (env takes precedence, then appConfig)
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
        if (appConfig?.openAiModel) model = appConfig.openAiModel.trim() || model;
        if (appConfig?.companyName) companyName = appConfig.companyName.trim() || companyName;
      } catch {
        // ignore config lookup error
      }
    }

    let generatedCopy: { title: string; shortText: string; hashtags: string[]; cta: string } | null = null;
    let detectedProduct = '';

    if (apiKey) {
      const systemPrompt = `Eres un experto en marketing digital para la empresa ${companyName} en Higüey, República Dominicana. 
Tu especialidad es seguridad electrónica, automatización del hogar y tecnología.
    Analizarás un diseño publicitario (imagen o video) y generarás copy de marketing alineado al producto o servicio que SE VE VISUALMENTE en el contenido.
    Debes describir QUÉ PRODUCTO o SERVICIO aparece en el contenido y generar copy exclusivamente para ESE producto.
    NUNCA generes copy para un producto distinto al que aparece en el contenido.
Responde ÚNICAMENTE con JSON válido.`;

      const userPrompt = `Analiza visualmente este ${isVideoDesign ? 'video' : 'diseño'} publicitario: ${designUrl}

    El contenido muestra un diseño final de publicidad de ${companyName}.

Tareas:
    1. Identifica el producto o servicio específico que aparece en el contenido (ej: motor de portón automático, cámara de seguridad, panel de alarma, control de acceso, etc.)
2. Genera copy de marketing en español dominicano para ESE producto específico

Devuelve exactamente este JSON:
{
  "detectedProduct": "nombre del producto/servicio detectado en la imagen",
  "title": "titular impactante de máx 8 palabras para el producto detectado",
  "shortText": "copy descriptivo de 15-25 palabras que destaque el beneficio del producto detectado",
  "hashtags": ["#hashtag1", "#hashtag2", "#hashtag3"],
  "cta": "llamado a la acción de 5-8 palabras"
}`;

      const modelCandidates = [model, 'gpt-4o', 'gpt-4o-mini'].filter((v, i, arr) => arr.indexOf(v) === i);

      for (const candidate of modelCandidates) {
        try {
            const raw = isVideoDesign
                ? await this.requestOpenAiVideoCopy({
                    apiKey,
                    model: candidate,
                    systemPrompt,
                    userPrompt,
                    videoUrl: designUrl,
                  })
                : await this.requestOpenAiImageCopy({
                    apiKey,
                    model: candidate,
                    systemPrompt,
                    userPrompt,
                    imageUrl: designUrl,
                  });

          if (raw == null || raw.trim().isEmpty) {
            continue;
          }

          // Extract JSON from potential markdown code blocks
          const jsonMatch = raw.match(/\{[\s\S]*\}/);
          if (!jsonMatch) {
            this.logger.warn(`[marketing-copy-from-design] No JSON in response with model ${candidate}`);
            continue;
          }
          const parsed = JSON.parse(jsonMatch[0]) as {
            detectedProduct?: unknown;
            title?: unknown;
            shortText?: unknown;
            hashtags?: unknown;
            cta?: unknown;
          };

          generatedCopy = {
            title: typeof parsed.title === 'string' ? parsed.title.trim() : '',
            shortText: typeof parsed.shortText === 'string' ? parsed.shortText.trim() : '',
            hashtags: Array.isArray(parsed.hashtags)
              ? (parsed.hashtags as unknown[]).filter((h) => typeof h === 'string').map((h) => `${h}`.trim())
              : [],
            cta: typeof parsed.cta === 'string' ? parsed.cta.trim() : '',
          };
          detectedProduct = typeof parsed.detectedProduct === 'string'
            ? parsed.detectedProduct.trim()
            : '';

          this.logger.log(
            `[marketing-copy-from-design] Generated copy for story ${storyId} — detected: ${parsed.detectedProduct ?? 'unknown'} — model: ${candidate}`,
          );
          break;
        } catch (err) {
          this.logger.warn(
            `[marketing-copy-from-design] Error with model ${candidate}: ${err instanceof Error ? err.message : String(err)}`,
          );
        }
      }
    } else {
      this.logger.warn('[marketing-copy-from-design] No OpenAI API key configured, skipping vision analysis.');
    }

    const metadata = this.asObject((story as any).imageGenerationMetadata) ?? {};
    // Update copy fields and mark that final design upload was completed.
    const updated = await this.prisma.marketingDailyStory.update({
      where: { id: story.id },
      data: {
        ...(generatedCopy?.title ? { title: generatedCopy.title } : {}),
        ...(generatedCopy?.shortText ? { shortText: generatedCopy.shortText } : {}),
        ...(generatedCopy?.hashtags?.length ? { hashtags: generatedCopy.hashtags } : {}),
        ...(generatedCopy?.cta ? { usedCTA: generatedCopy.cta } : {}),
        imageGenerationMetadata: {
          ...metadata,
          finalDesignUploaded: true,
          finalDesignImageUrl: designUrl,
          finalDesignMediaType: isVideoDesign ? 'video' : 'image',
          finalDesignSyncedAt: new Date().toISOString(),
        } as any,
      },
      include: {
        approvedByUser: { select: { id: true, nombreCompleto: true } },
        mediaAsset: true,
      },
    });

    await this.upsertPublishedFinalDesignAsset({
      companyId,
      storyId,
      userId,
      imageUrl: designUrl,
      storyType: story.type,
      title: generatedCopy?.title || story.title,
      shortText: generatedCopy?.shortText || story.shortText,
      hashtags: generatedCopy?.hashtags?.length ? generatedCopy.hashtags : this.safeStringArray((story as any).hashtags),
      detectedProduct,
    });

    try {
      await this.prisma.marketingActivityLog.create({
        data: {
          companyId,
          action: 'MARKETING_COPY_REGENERATED_FROM_DESIGN',
          description: `Copy regenerado desde imagen de diseño para contenido ${storyId}`,
          userId,
          metadata: { storyId, aiUsed: !!generatedCopy },
        },
      });
    } catch {
      // activity log is non-critical
    }

    return updated;
  }

  private isVideoUrl(url: string): boolean {
    const value = `${url ?? ''}`.trim().toLowerCase();
    return /\.(mp4|mov|m4v|webm|mkv)(\?|$)/i.test(value);
  }

  private async isRemoteVideoByContentType(url: string): Promise<boolean> {
    const normalized = `${url ?? ''}`.trim();
    if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
      return false;
    }

    const parseContentType = (raw: string | null) =>
      `${raw ?? ''}`
        .split(';')
        .map((part) => part.trim().toLowerCase())[0] || '';

    try {
      const head = await fetch(normalized, { method: 'HEAD' });
      const contentType = parseContentType(head.headers.get('content-type'));
      if (contentType.startsWith('video/')) {
        return true;
      }
    } catch {
      // Some storage providers block HEAD; fallback to ranged GET below.
    }

    try {
      const probe = await fetch(normalized, {
        method: 'GET',
        headers: { Range: 'bytes=0-0' },
      });
      const contentType = parseContentType(probe.headers.get('content-type'));
      return contentType.startsWith('video/');
    } catch (error) {
      this.logger.debug(
        `[marketing-copy-from-design] Unable to probe content-type for URL ${normalized}: ${error instanceof Error ? error.message : String(error)}`,
      );
      return false;
    }
  }

  private async requestOpenAiImageCopy(params: {
    apiKey: string;
    model: string;
    systemPrompt: string;
    userPrompt: string;
    imageUrl: string;
  }): Promise<string | null> {
    const { apiKey, model, systemPrompt, userPrompt, imageUrl } = params;
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model,
        temperature: 0.4,
        messages: [
          { role: 'system', content: systemPrompt },
          {
            role: 'user',
            content: [
              {
                type: 'image_url',
                image_url: { url: imageUrl, detail: 'high' },
              },
              { type: 'text', text: userPrompt },
            ],
          },
        ],
      }),
    });

    if (!response.ok) {
      this.logger.warn(
        `[marketing-copy-from-design] OpenAI image HTTP ${response.status} with model ${model}`,
      );
      return null;
    }

    const payload = (await response.json()) as {
      choices?: Array<{ message?: { content?: string } }>;
    };
    return payload.choices?.[0]?.message?.content?.trim() ?? null;
  }

  private async requestOpenAiVideoCopy(params: {
    apiKey: string;
    model: string;
    systemPrompt: string;
    userPrompt: string;
    videoUrl: string;
  }): Promise<string | null> {
    const { apiKey, model, systemPrompt, userPrompt, videoUrl } = params;
    const response = await fetch('https://api.openai.com/v1/responses', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model,
        temperature: 0.4,
        input: [
          {
            role: 'system',
            content: [{ type: 'input_text', text: systemPrompt }],
          },
          {
            role: 'user',
            content: [
              { type: 'input_text', text: userPrompt },
              { type: 'input_video', video_url: videoUrl },
            ],
          },
        ],
      }),
    });

    if (!response.ok) {
      this.logger.warn(
        `[marketing-copy-from-design] OpenAI video HTTP ${response.status} with model ${model}`,
      );
      return null;
    }

    const payload = (await response.json()) as Record<string, unknown>;
    const outputText = `${payload['output_text'] ?? ''}`.trim();
    if (outputText.length > 0) return outputText;

    const output = Array.isArray(payload['output']) ? payload['output'] : [];
    for (const item of output) {
      if (!item || typeof item !== 'object') continue;
      const content = Array.isArray((item as Record<string, unknown>)['content'])
        ? ((item as Record<string, unknown>)['content'] as unknown[])
        : [];
      for (const part of content) {
        if (!part || typeof part !== 'object') continue;
        const partObj = part as Record<string, unknown>;
        const text = `${partObj['text'] ?? ''}`.trim();
        if (text.length > 0) {
          return text;
        }
      }
    }
    return null;
  }

  private async upsertPublishedFinalDesignAsset(params: {
    companyId: string;
    storyId: string;
    userId: string;
    imageUrl: string;
    storyType: MarketingStoryType;
    title: string;
    shortText: string;
    hashtags: string[];
    detectedProduct: string;
  }) {
    const {
      companyId,
      storyId,
      userId,
      imageUrl,
      storyType,
      title,
      shortText,
      hashtags,
      detectedProduct,
    } = params;

    const relatedStoryTag = `related-story:${storyId}`;
    const baseTags: string[] = [
      'diseno-final',
      'estado-publicado',
      'origen:estado_diario',
      'usado-en:estados',
      relatedStoryTag,
      ...hashtags,
    ];
    if (detectedProduct.trim().length > 0) {
      baseTags.push(`producto:${detectedProduct.trim().toLowerCase().replace(/\s+/g, '-')}`);
    }
    const normalizedTags: string[] = [
      ...new Set(baseTags.map((item: string) => item.trim()).filter((item: string) => item.length > 0)),
    ];

    const relatedService = detectedProduct.trim().length > 0
      ? detectedProduct.trim()
      : this.storyTypeLabel(storyType);
    const category = this.storyTypeCategory(storyType);
    const fileName = `estado-${storyId}-final.jpg`;
    const description =
      `diseno final subido para estado diario | relatedStoryId=${storyId} | usadoEn=estados | estado=publicado` +
      (shortText.trim().length > 0 ? ` | copy=${shortText.trim()}` : '');

    const candidates = await this.prisma.marketingMediaAsset.findMany({
      where: {
        companyId,
        fileUrl: imageUrl,
      },
      orderBy: [{ updatedAt: 'desc' }],
      take: 10,
    });

    const existing = candidates.find((item) => {
      const tags = Array.isArray(item.tags)
        ? item.tags.map((tag) => `${tag}`.trim().toLowerCase())
        : [];
      return tags.includes(relatedStoryTag.toLowerCase());
    });

    if (existing) {
      await this.prisma.marketingMediaAsset.update({
        where: { id: existing.id },
        data: {
          thumbnailUrl: imageUrl,
          category,
          relatedService,
          tags: normalizedTags as any,
          description,
          isActive: true,
        },
      });
      return;
    }

    const created = await this.prisma.marketingMediaAsset.create({
      data: {
        companyId,
        fileUrl: imageUrl,
        thumbnailUrl: imageUrl,
        fileName,
        mimeType: 'image/jpeg',
        category,
        relatedService,
        tags: normalizedTags as any,
        description,
        isActive: true,
        isFeatured: false,
      },
    });

    await this.logAssetUsage(companyId, created.id, userId, {
      storyId,
      source: 'final-design-upload',
      finalDesignUploaded: true,
      title: title.trim(),
    });
  }

  private storyTypeCategory(type: MarketingStoryType) {
    if (type === MarketingStoryType.SALES) return 'Estado publicado - Ventas';
    if (type === MarketingStoryType.TRUST) return 'Estado publicado - Confianza';
    return 'Estado publicado - Educativo';
  }

  private storyTypeLabel(type: MarketingStoryType) {
    if (type === MarketingStoryType.SALES) return 'Ventas';
    if (type === MarketingStoryType.TRUST) return 'Confianza';
    return 'Educativo';
  }

  private toDateOnly(value: Date) {
    const year = value.getUTCFullYear();
    const month = `${value.getUTCMonth() + 1}`.padStart(2, '0');
    const day = `${value.getUTCDate()}`.padStart(2, '0');
    return `${year}-${month}-${day}`;
  }
}
