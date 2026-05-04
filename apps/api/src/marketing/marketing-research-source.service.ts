import { Injectable, Logger } from '@nestjs/common';

export type ResearchInput = {
  researchPrompt: string;
  businessName: string;
  businessLocation: string;
  businessDescription: string;
  mainServices: string[];
  priorityServices: string[];
  targetMarket: string;
  brandTone: string;
  learningInsights: string[];
};

export type ResearchOutput = {
  marketSummary: string;
  competitorPublishingPatterns: string;
  commonOffers: string;
  observedPriceRanges: string;
  strongAngles: string[];
  weakAngles: string[];
  contentOpportunities: string;
  recommendedProducts: string[];
  recommendedContentTypes: string[];
  recommendedOffers: string[];
  recommendedHooks: string[];
  recommendedCTAs: string[];
  doMoreOfThis: string[];
  avoidThis: string[];
  confidenceScore: number;
  dataSources: string[];
};

@Injectable()
export class MarketingResearchSourceService {
  private readonly logger = new Logger(MarketingResearchSourceService.name);

  async generateResearch(input: ResearchInput): Promise<ResearchOutput> {
    this.logger.log(`Generando investigacion para: ${input.businessName} - ${input.businessLocation}`);
    // NOTE: Mock implementation. Replace with real AI/Meta Ad Library when credentials are available.
    return this.mockResearch(input);
  }

  private mockResearch(input: ResearchInput): ResearchOutput {
    const priority = input.priorityServices[0] ?? 'motores de portones';

    return {
      marketSummary: `Análisis mock del mercado de seguridad e instalación en República Dominicana. Principal foco: ${priority}. El mercado muestra demanda creciente de automatización residencial y comercial. FULLTECH tiene oportunidad en Higüey y La Altagracia donde la competencia formalizada es baja. Fuente: datos internos y patrones observados del mercado dominicano.`,
      competitorPublishingPatterns: `Competidores publican principalmente fotos de instalaciones terminadas. Frecuencia: 3-5 publicaciones/semana. Usan precios aproximados como gancho. Poco uso de videos. Baja calidad de copys. Poca consistencia de marca.`,
      commonOffers: `Instalación gratis con equipo. Mantenimiento incluido primer año. Cuotas sin intereses. Descuentos por referidos. Paquetes combinados cámara + motor.`,
      observedPriceRanges: `ESTIMADO (no verificado): Motores portones: RD$8,000-RD$25,000. Cámaras básicas: RD$3,500-RD$8,000/unidad. Instalación: varía según proyecto. Cercos eléctricos: RD$15,000-RD$40,000.`,
      strongAngles: [
        'Garantía real post-instalación',
        'Técnicos certificados locales',
        'Respuesta rápida en Higüey',
        'Financiamiento disponible',
        'Combinación cámara + motor',
      ],
      weakAngles: [
        'Precio sin contexto de valor',
        'Especificaciones técnicas sin traducir a beneficios',
      ],
      contentOpportunities: `1. Videos cortos de instalación en proceso. 2. Testimonios de clientes reales de Higüey. 3. Comparativo antes/después. 4. Contenido educativo "¿Cuánto cuesta un motor de portón?". 5. Stories de urgencia: "Solo 5 instalaciones disponibles esta semana".`,
      recommendedProducts: ['Motor de portón eléctrico', 'Cámara de seguridad HD', 'Cerco eléctrico', 'Intercom IP'],
      recommendedContentTypes: ['Historia de Instagram 9:16', 'Reels 15-30s', 'Post cuadrado', 'Carrusel educativo'],
      recommendedOffers: ['Instalación gratis', 'Garantía extendida', 'Paquete combo', 'Cuotas sin intereses'],
      recommendedHooks: [
        '¿Tu portón sigue siendo manual en 2026?',
        'La cámara que protege tu negocio 24/7',
        'Instala hoy, paga después',
        'Higüey ya se está modernizando',
      ],
      recommendedCTAs: [
        'Llámanos ahora',
        'Solicita tu cotización gratis',
        'WhatsApp directo',
        'Agenda tu visita técnica',
      ],
      doMoreOfThis: ['Contenido local con referencias a Higüey', 'Fotos reales de instalaciones', 'Respuestas rápidas a comentarios'],
      avoidThis: ['Precios sin contexto', 'Fotos genéricas de stock', 'Textos muy largos sin CTA claro'],
      confidenceScore: 0.45,
      dataSources: ['mock/internal', 'manual/patterns', 'market-observation'],
    };
  }
}
