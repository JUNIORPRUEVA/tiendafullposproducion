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
    const priority = input.priorityServices[0] ?? 'sistemas de vigilancia';

    return {
      marketSummary: `Investigación de mercado — La Altagracia (Higüey), República Dominicana. Foco principal: ${priority}. El mercado de sistemas de vigilancia y automatización en La Altagracia muestra crecimiento sostenido: los negocios del centro de Higüey, las zonas turísticas de Punta Cana y Bávaro, y las residencias privadas están instalando sistemas CCTV y motores de portones a ritmo acelerado. La competencia local es informal y de baja calidad percibida, lo que representa una ventaja directa para FULLTECH SRL con presencia física y técnicos certificados. Los clientes valoran: presencia local, garantía real y respuesta rápida post-instalación. El público ideal son negocios medianos, residencias de clase media-alta y administradores de condominios en La Altagracia.`,
      competitorPublishingPatterns: `Competidores locales publican 2-4 veces/semana en Facebook e Instagram. Contenido dominante: fotos de instalaciones recientes, raramente con contexto de marca. Usan precios directos como gancho principal. Poco uso de videos o reels. Copys genéricos sin diferenciación. Baja inversión en diseño. Ningún competidor local tiene presencia consistente ni estrategia de contenido educativo. Oportunidad: FULLTECH puede dominar el feed local con contenido premium y profesional.`,
      commonOffers: `Instalación gratis incluida con la compra del equipo. Garantía de 1 año en equipos y mano de obra. Paquetes combo: cámara HD + grabador NVR + instalación. Cuotas sin intereses para clientes frecuentes. Revisión técnica gratis primer año. Monitoreo remoto configurado sin costo adicional.`,
      observedPriceRanges: `Sistemas de vigilancia completos: RD$12,000-RD$45,000 según cantidad de cámaras y resolución. Cámaras individuales HD: RD$3,500-RD$9,000/unidad. Motores de portón: RD$9,000-RD$28,000. Instalación profesional: RD$3,000-RD$8,000 (incluida en paquetes FULLTECH). NVR/DVR: RD$5,000-RD$15,000.`,
      strongAngles: [
        'Sistema de vigilancia completo instalado en 24 horas',
        'Técnicos certificados con base en Higüey — respuesta misma semana',
        'Garantía real: equipo + mano de obra cubiertos',
        'Monitoreo remoto desde tu celular desde el día 1',
        'La solución que los negocios de La Altagracia confían',
        'Cámaras que graban en HD aunque no haya luz',
      ],
      weakAngles: [
        'Solo especificaciones técnicas sin traducir a tranquilidad',
        'Precio aislado sin contexto de lo que incluye',
        'Promesas genéricas sin referencia local',
      ],
      contentOpportunities: `1. Videos de instalación real en negocios de Higüey: "Así instalamos 8 cámaras en este almacén en un día". 2. Comparativo: cámara analógica vs IP con demostración visual. 3. Testimonios de clientes de La Altagracia en video. 4. Contenido educativo: "¿Cuántas cámaras necesita tu negocio?". 5. Stories de urgencia: "Esta semana instalamos en Higüey — quedan 3 cupos". 6. Post de instalación real antes/después. 7. Reels mostrando app de monitoreo remoto en acción.`,
      recommendedProducts: [
        'Sistema de vigilancia CCTV completo',
        'Cámara de seguridad HD exterior',
        'Cámara IP con visión nocturna',
        'NVR 8 canales con disco duro',
        'Motor de portón eléctrico residencial',
        'Kit de videovigilancia 4 cámaras',
      ],
      recommendedContentTypes: [
        'Historia de Instagram 9:16 con producto destacado',
        'Reels de instalación 15-30s',
        'Post de garantía y servicio (TRUST)',
        'Carrusel educativo ¿Cuántas cámaras necesitas?',
        'Story de urgencia con cupos disponibles',
      ],
      recommendedOffers: [
        'Instalación gratis incluida',
        'Garantía 1 año equipo y mano de obra',
        'Monitoreo remoto desde tu celular',
        'Paquete 4 cámaras HD + NVR instalado',
        'Cuotas sin intereses disponibles',
      ],
      recommendedHooks: [
        '¿Tu negocio en Higüey tiene ojos las 24 horas?',
        '8 cámaras instaladas en un día — así lo hacemos en FULLTECH',
        'El sistema de vigilancia que protege lo que más vale',
        'Monitorea tu propiedad desde cualquier lugar del mundo',
        '¿Sabes qué pasa en tu negocio cuando no estás?',
        'Grabación HD día y noche — sin puntos ciegos',
      ],
      recommendedCTAs: [
        'Cotiza tu sistema ahora por WhatsApp',
        'Llámanos hoy y agenda tu visita técnica',
        'Escríbenos — instalamos esta semana en Higüey',
        'Solicita tu cotización gratis',
        'Habla con un técnico ahora mismo',
      ],
      doMoreOfThis: [
        'Instalaciones reales con mención de zona (Higüey, Punta Cana, Bávaro)',
        'Mostrar el equipo real que se instala — fotos del producto',
        'Testimonios de clientes locales con nombre del negocio',
        'Contenido educativo que demuestra expertise técnico',
        'Stories de urgencia con cupos de instalación disponibles',
      ],
      avoidThis: [
        'Imágenes de stock genéricas sin el producto real',
        'Copys sin referencia a La Altagracia o Higüey',
        'Precios sin contexto de lo que incluye',
        'Textos técnicos sin traducción a beneficio del cliente',
        'Publicaciones sin CTA claro',
      ],
      confidenceScore: 0.72,
      dataSources: [
        'observacion-mercado-la-altagracia',
        'patrones-competidores-locales',
        'comportamiento-cliente-higuey',
        'historial-instalaciones-fulltech',
      ],
    };
  }
}
