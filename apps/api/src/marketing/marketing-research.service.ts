import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { MarketingLearningService } from './marketing-learning.service';
import { MarketingResearchSourceService } from './marketing-research-source.service';
import { GenerateResearchDto, UpdateMarketingResearchConfigDto } from './dto/marketing-research.dto';

@Injectable()
export class MarketingResearchService {
  private readonly logger = new Logger(MarketingResearchService.name);
  private static readonly WEEKLY_RESEARCH_DAYS = 7;
  private readonly strictResearchScope = `\n\nREGLA ESTRICTA DE ALCANCE (OBLIGATORIO):\n- Investigar SOLO temas de venta, publicidad, comportamiento del cliente y conversion comercial.\n- Investigar SOLO estos rubros prioritarios: camaras de seguridad, motores de porton, alarmas, cercos electricos, POS, computadoras para negocios, automatizacion y control de acceso.\n- Investigar SOLO en estas zonas: Republica Dominicana, La Altagracia (Higuey) y La Romana.\n- Priorizar evidencia de marketplace Facebook, anuncios locales, TikTok, Instagram, publicaciones comerciales y comentarios de clientes.\n- Excluir por completo politica, gobierno, macroeconomia, noticias nacionales largas, articulos institucionales y cualquier ruido informativo no comercial.\n- Responder en formato practico y accionable: bloques cortos, bullets y sin parrafos largos.\n- Si no hay hallazgos relevantes, devolver explicitamente que no hay evidencia suficiente dentro del alcance en lugar de salir del tema.`;

  private readonly defaultPrompt = `Generar inteligencia comercial para publicidad de FULLTECH SRL (Higuey, La Altagracia, Republica Dominicana) con enfoque 100% ventas.

Objetivo real:
- Crear anuncios, estados, reels y campanas que conviertan.
- Detectar patrones de compra local, objeciones y ofertas que mejor responden.
- Entregar ideas listas para publicar hoy.

Prioridad alta de investigacion:
1) Camaras de seguridad
2) Motores de porton
3) Alarmas
4) Cercos electricos
5) POS
6) Computadoras para negocios
7) Automatizacion
8) Control de acceso

Buscar y sintetizar:
- Que estan comprando las personas y como lo compran
- Que copys, formatos y videos generan respuesta
- Que promociones y CTA convierten
- Preguntas frecuentes, objeciones y miedos del cliente
- Que hace confiar al comprador local

Formato de salida obligatorio:
- Bloques visuales cortos con bullets
- Nada de parrafos largos, lenguaje institucional o analisis academico
- Incluir seccion "Contenido recomendado hoy" con: estado recomendado + idea de video + CTA sugerido.`;

  constructor(
    private readonly prisma: PrismaService,
    private readonly source: MarketingResearchSourceService,
    private readonly learning: MarketingLearningService,
  ) {}

  async getOrCreateConfig(companyId: string) {
    const existing = await this.prisma.marketingResearchConfig.findUnique({ where: { companyId } });
    if (existing) {
      if (existing.researchFrequencyDays !== MarketingResearchService.WEEKLY_RESEARCH_DAYS) {
        return this.prisma.marketingResearchConfig.update({
          where: { id: existing.id },
          data: { researchFrequencyDays: MarketingResearchService.WEEKLY_RESEARCH_DAYS },
        });
      }
      return existing;
    }
    return this.prisma.marketingResearchConfig.create({
      data: {
        companyId,
        defaultResearchPrompt: this.defaultPrompt,
        businessName: 'FULLTECH SRL',
        businessLocation: 'Higüey, La Altagracia, República Dominicana',
        businessDescription: 'Empresa dominicana especializada en seguridad e instalación tecnológica para hogares y negocios.',
        mainServices: [
          'Automatización de motores para portones eléctricos',
          'Instalación de cámaras de seguridad',
          'Cercos eléctricos',
          'Intercoms',
          'Alarmas',
          'Sistemas POS',
          'Tecnología para negocios',
        ],
        priorityServices: [
          'Motores de portones eléctricos',
          'Cámaras de seguridad',
          'Cercos eléctricos',
          'Intercoms',
          'Alarmas',
        ],
        targetMarket: 'Negocios y residencias en Higüey, La Altagracia y República Dominicana.',
        brandTone: 'Profesional, confiable, claro, dominicano, directo, moderno, orientado a ventas.',
        learningEnabled: true,
        researchFrequencyDays: MarketingResearchService.WEEKLY_RESEARCH_DAYS,
        requireApproval: false,
        city: 'Higüey',
        province: 'La Altagracia',
        country: 'República Dominicana',
        serviceRadiusKm: 25,
        serviceZones: ['Higüey', 'La Altagracia', 'San Pedro de Macorís', 'La Romana'],
        defaultCTA: 'Llámanos o escríbenos por WhatsApp',
        businessHours: 'Lun–Vie 8:00am–6:00pm · Sáb 8:00am–1:00pm',
      },
    });
  }

  async updateConfig(companyId: string, dto: UpdateMarketingResearchConfigDto, userId: string) {
    const config = await this.getOrCreateConfig(companyId);
    const hasFrequencyOverride = dto.research_frequency_days != null;
    return this.prisma.marketingResearchConfig.update({
      where: { id: config.id },
      data: {
        ...(dto.default_research_prompt != null ? { defaultResearchPrompt: dto.default_research_prompt.trim() } : {}),
        ...(dto.business_name != null ? { businessName: dto.business_name.trim() } : {}),
        ...(dto.business_location != null ? { businessLocation: dto.business_location.trim() } : {}),
        ...(dto.business_description != null ? { businessDescription: dto.business_description.trim() } : {}),
        ...(dto.main_services != null ? { mainServices: dto.main_services.map((s) => s.trim()).filter((s) => s.length > 0) } : {}),
        ...(dto.priority_services != null ? { priorityServices: dto.priority_services.map((s) => s.trim()).filter((s) => s.length > 0) } : {}),
        ...(dto.target_market != null ? { targetMarket: dto.target_market.trim() } : {}),
        ...(dto.brand_tone != null ? { brandTone: dto.brand_tone.trim() } : {}),
        ...(dto.learning_enabled != null ? { learningEnabled: dto.learning_enabled } : {}),
        ...(hasFrequencyOverride
          ? { researchFrequencyDays: MarketingResearchService.WEEKLY_RESEARCH_DAYS }
          : {}),
        // requireApproval is always false — research auto-approved
        requireApproval: false,
        // New company profile fields
        ...(dto.phone != null ? { phone: dto.phone.trim() } : {}),
        ...(dto.address != null ? { address: dto.address.trim() } : {}),
        ...(dto.city != null ? { city: dto.city.trim() } : {}),
        ...(dto.province != null ? { province: dto.province.trim() } : {}),
        ...(dto.country != null ? { country: dto.country.trim() } : {}),
        ...(dto.latitude != null ? { latitude: dto.latitude } : {}),
        ...(dto.longitude != null ? { longitude: dto.longitude } : {}),
        ...(dto.service_radius_km != null ? { serviceRadiusKm: dto.service_radius_km } : {}),
        ...(dto.service_zones != null ? { serviceZones: dto.service_zones.map((z) => z.trim()).filter((z) => z.length > 0) } : {}),
        ...(dto.default_cta != null ? { defaultCTA: dto.default_cta.trim() } : {}),
        ...(dto.brand_colors != null ? { brandColors: dto.brand_colors.map((c) => c.trim()).filter((c) => c.length > 0) } : {}),
        ...(dto.business_hours != null ? { businessHours: dto.business_hours.trim() } : {}),
        ...(dto.internal_notes != null ? { internalNotes: dto.internal_notes.trim() } : {}),
        updatedByUserId: userId,
      },
    });
  }

  async getLatestResearch(companyId: string) {
    return this.prisma.marketingResearch.findFirst({
      where: { companyId },
      orderBy: { createdAt: 'desc' },
    });
  }

  async getUsableResearch(companyId: string) {
    const config = await this.getOrCreateConfig(companyId);
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - MarketingResearchService.WEEKLY_RESEARCH_DAYS);

    return this.prisma.marketingResearch.findFirst({
      where: {
        companyId,
        status: { in: ['APPROVED', 'DRAFT'] },
        createdAt: { gte: cutoff },
      },
      orderBy: { createdAt: 'desc' },
    });
  }

  async generate(companyId: string, dto: GenerateResearchDto, userId: string, forced = false) {
    const config = await this.getOrCreateConfig(companyId);
    const insights = await this.learning.getActiveInsights(companyId, 15);
    const insightTexts = insights.map((i) => `[${i.category}] ${i.insight}`);

    const basePrompt = dto.custom_prompt?.trim() || config.defaultResearchPrompt;
    const prompt = this.applyStrictScope(basePrompt);

    this.logger.log(`Generando investigacion de mercado para companyId=${companyId} forced=${forced}`);

    const result = await this.source.generateResearch({
      researchPrompt: prompt,
      businessName: config.businessName,
      businessLocation: config.businessLocation,
      businessDescription: config.businessDescription ?? '',
      mainServices: config.mainServices,
      priorityServices: config.priorityServices,
      targetMarket: config.targetMarket ?? '',
      brandTone: config.brandTone,
      learningInsights: insightTexts,
    });

    const now = new Date();
    const today = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));

    const research = await this.prisma.marketingResearch.create({
      data: {
        companyId,
        date: today,
        researchPrompt: prompt,
        businessSnapshot: {
          name: config.businessName,
          location: config.businessLocation,
          services: config.mainServices,
          priority: config.priorityServices,
          tone: config.brandTone,
        },
        country: 'República Dominicana',
        city: 'Higüey',
        mainFocus: config.priorityServices[0] ?? 'Seguridad e instalación',
        servicesAnalyzed: config.mainServices,
        marketSummary: result.marketSummary,
        competitorPublishingPatterns: result.competitorPublishingPatterns,
        commonOffers: result.commonOffers,
        observedPriceRanges: result.observedPriceRanges,
        strongAngles: result.strongAngles,
        weakAngles: result.weakAngles,
        contentOpportunities: result.contentOpportunities,
        recommendedProducts: result.recommendedProducts,
        recommendedContentTypes: result.recommendedContentTypes,
        recommendedOffers: result.recommendedOffers,
        recommendedHooks: result.recommendedHooks,
        recommendedCTAs: result.recommendedCTAs,
        doMoreOfThis: result.doMoreOfThis,
        avoidThis: result.avoidThis,
        confidenceScore: result.confidenceScore,
        dataSources: result.dataSources,
        status: config.requireApproval ? 'DRAFT' : 'APPROVED',
        forcedByUserId: forced ? userId : null,
      },
    });

    if (config.learningEnabled) {
      await this.learning.extractAndSave(
        companyId,
        research.id,
        result.strongAngles,
        result.avoidThis,
        result.recommendedOffers,
      );
    }

    await this.prisma.marketingActivityLog.create({
      data: {
        companyId,
        action: forced ? 'MARKETING_RESEARCH_FORCED' : 'MARKETING_RESEARCH_GENERATED',
        description: `Investigacion de mercado ${forced ? 'forzada' : 'generada'} para ${config.businessName}`,
        userId,
        metadata: { researchId: research.id, confidenceScore: result.confidenceScore },
      },
    });

    return research;
  }

  async approve(companyId: string, researchId: string, userId: string) {
    const research = await this.prisma.marketingResearch.findFirst({ where: { id: researchId, companyId } });
    if (!research) throw new NotFoundException('Investigacion no encontrada');

    const updated = await this.prisma.marketingResearch.update({
      where: { id: researchId },
      data: { status: 'APPROVED', approvedByUserId: userId, approvedAt: new Date() },
    });

    await this.prisma.marketingActivityLog.create({
      data: {
        companyId,
        action: 'MARKETING_RESEARCH_APPROVED',
        description: 'Investigacion de mercado aprobada',
        userId,
        metadata: { researchId },
      },
    });

    return updated;
  }

  async reject(companyId: string, researchId: string, userId: string, reason?: string) {
    const research = await this.prisma.marketingResearch.findFirst({ where: { id: researchId, companyId } });
    if (!research) throw new NotFoundException('Investigacion no encontrada');

    const updated = await this.prisma.marketingResearch.update({
      where: { id: researchId },
      data: { status: 'REJECTED', rejectedAt: new Date() },
    });

    await this.prisma.marketingActivityLog.create({
      data: {
        companyId,
        action: 'MARKETING_RESEARCH_REJECTED',
        description: `Investigacion rechazada: ${reason ?? ''}`,
        userId,
        metadata: { researchId, reason },
      },
    });

    if (reason && research.strongAngles && Array.isArray(research.strongAngles)) {
      for (const angle of research.strongAngles as string[]) {
        await this.learning.penalizeInsight(companyId, angle);
      }
    }

    return updated;
  }

  private applyStrictScope(basePrompt: string): string {
    const prompt = basePrompt.trim();
    if (!prompt) return this.strictResearchScope.trim();
    return `${prompt}${this.strictResearchScope}`;
  }

  async getList(companyId: string) {
    return this.prisma.marketingResearch.findMany({
      where: { companyId },
      orderBy: { createdAt: 'desc' },
    });
  }

  async getLearningStats(companyId: string) {
    const [activeCount, discardedCount] = await Promise.all([
      this.prisma.marketingLearningMemory.count({ where: { companyId, status: 'ACTIVE' } }),
      this.prisma.marketingLearningMemory.count({ where: { companyId, status: 'DISCARDED' } }),
    ]);
    const topInsights = await this.learning.getActiveInsights(companyId, 5);
    return { activeCount, discardedCount, topInsights };
  }
}
