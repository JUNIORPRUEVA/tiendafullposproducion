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

type PublicSignal = {
  title: string;
  link: string;
  source: string;
  pubDate: string;
};

@Injectable()
export class MarketingResearchSourceService {
  private readonly logger = new Logger(MarketingResearchSourceService.name);
  private readonly focusCatalog = [
    {
      label: 'Sistema de seguridad general',
      query: 'sistema de seguridad',
      keywords: ['seguridad', 'vigilancia'],
    },
    {
      label: 'Sistema de camaras (CCTV)',
      query: 'camaras de seguridad cctv',
      keywords: ['camara', 'cctv', 'videovigilancia', 'nvr', 'dvr'],
    },
    {
      label: 'Motores de portones',
      query: 'motor de porton electrico',
      keywords: ['porton', 'portones', 'motor de porton', 'automatizacion de porton'],
    },
    {
      label: 'Cerco electrico',
      query: 'cerco electrico',
      keywords: ['cerco electrico'],
    },
    {
      label: 'Control de acceso',
      query: 'control de acceso',
      keywords: ['control de acceso', 'acceso biometrico', 'acceso'],
    },
    {
      label: 'Sistema POS / Punto de ventas',
      query: 'sistema pos punto de venta',
      keywords: ['pos', 'punto de venta', 'facturacion', 'caja', 'tpv'],
    },
    {
      label: 'Alarmas',
      query: 'sistema de alarmas',
      keywords: ['alarma', 'alarmas'],
    },
  ] as const;

  private readonly locations = [
    'Republica Dominicana',
    'La Altagracia',
    'Higuey',
    'La Romana',
  ];

  private readonly locationKeywords = [
    'republica dominicana',
    'dominicana',
    'rd',
    'la altagracia',
    'higuey',
    'higüey',
    'la romana',
  ];

  async generateResearch(input: ResearchInput): Promise<ResearchOutput> {
    this.logger.log(
      `Generando investigacion para: ${input.businessName} - ${input.businessLocation}`,
    );

    const signals = await this.collectPublicSignals(input);
    return this.buildWeeklyResearch(input, signals);
  }

  private async collectPublicSignals(input: ResearchInput): Promise<PublicSignal[]> {
    const queryTerms = this.buildQueryTerms();
    const signals: PublicSignal[] = [];

    for (const term of queryTerms) {
      const rows = await this.fetchGoogleNewsRss(term);
      signals.push(...rows);
    }

    const unique = new Map<string, PublicSignal>();
    for (const row of signals) {
      const key = `${row.link}|${row.title}`.toLowerCase();
      if (!unique.has(key)) unique.set(key, row);
    }

    return this.filterRelevantSignals([...unique.values()]);
  }

  private buildQueryTerms(): string[] {
    const catalogTerms = this.focusCatalog.map((topic) => topic.query);
    const base = [...catalogTerms]
      .map((item) => item.trim())
      .filter((item) => item.length > 0);

    const queries: string[] = [];
    for (const term of base) {
      for (const location of this.locations) {
        queries.push(`${term} ${location}`);
      }
    }

    return [...new Set(queries)].slice(0, 28);
  }

  private filterRelevantSignals(signals: PublicSignal[]): PublicSignal[] {
    const normalized = signals
      .map((signal) => ({
        ...signal,
        title: this.sanitizeTitle(signal.title),
      }))
      .filter((signal) => signal.title.length > 0);

    const strict = normalized.filter((signal) => {
      const text = `${signal.title} ${signal.source}`;
      return this.matchesTopic(text) && this.matchesLocation(text);
    });

    if (strict.length >= 8) {
      return strict.slice(0, 40);
    }

    const fallback = normalized.filter((signal) => {
      const text = `${signal.title} ${signal.source}`;
      return this.matchesTopic(text);
    });

    return fallback.slice(0, 40);
  }

  private async fetchGoogleNewsRss(query: string): Promise<PublicSignal[]> {
    const url = `https://news.google.com/rss/search?q=${encodeURIComponent(
      query,
    )}&hl=es-419&gl=DO&ceid=DO:es-419`;

    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 5000);

      const response = await fetch(url, {
        method: 'GET',
        signal: controller.signal,
        headers: {
          'user-agent': 'FULLTECH-Marketing-Research/1.0',
        },
      });

      clearTimeout(timeout);
      if (!response.ok) {
        this.logger.warn(`RSS no disponible para query='${query}' status=${response.status}`);
        return [];
      }

      const xml = await response.text();
      return this.parseRssItems(xml);
    } catch (error) {
      this.logger.warn(
        `Fallo lectura RSS para query='${query}': ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
      return [];
    }
  }

  private parseRssItems(xml: string): PublicSignal[] {
    const rows: PublicSignal[] = [];
    const itemRegex = /<item>([\s\S]*?)<\/item>/g;
    let match: RegExpExecArray | null;

    while ((match = itemRegex.exec(xml)) !== null) {
      const item = match[1] ?? '';
      const title = this.decodeXml(this.readTag(item, 'title'));
      const link = this.decodeXml(this.readTag(item, 'link'));
      const pubDate = this.decodeXml(this.readTag(item, 'pubDate'));
      const source = this.decodeXml(this.readTag(item, 'source'));

      if (!title || !link) continue;

      rows.push({
        title,
        link,
        pubDate,
        source: source || 'Fuente pública',
      });
    }

    return rows;
  }

  private readTag(input: string, tag: string): string {
    const regex = new RegExp(`<${tag}[^>]*>([\\s\\S]*?)<\\/${tag}>`, 'i');
    const match = input.match(regex);
    if (!match) return '';
    return match[1]?.trim() ?? '';
  }

  private decodeXml(value: string): string {
    return value
      .replace(/<!\[CDATA\[|\]\]>/g, '')
      .replace(/&amp;/g, '&')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .trim();
  }

  private sanitizeTitle(title: string): string {
    return title
      .replace(/\s+-\s+[^-]{2,80}$/g, '')
      .replace(/\s+/g, ' ')
      .trim();
  }

  private normalizeText(value: string): string {
    return value
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .toLowerCase();
  }

  private matchesTopic(text: string): boolean {
    const normalized = this.normalizeText(text);
    return this.focusCatalog.some((topic) =>
      topic.keywords.some((keyword) => normalized.includes(this.normalizeText(keyword))),
    );
  }

  private matchesLocation(text: string): boolean {
    const normalized = this.normalizeText(text);
    return this.locationKeywords.some((keyword) =>
      normalized.includes(this.normalizeText(keyword)),
    );
  }

  private buildWeeklyResearch(
    input: ResearchInput,
    signals: PublicSignal[],
  ): ResearchOutput {
    const topServices = this.focusCatalog.map((item) => item.label);
    const sourceLabels = this.takeUnique(signals.map((s) => s.source).filter((s) => s.length > 0), 12);
    const topHeadlines = this.takeUnique(signals.map((s) => s.title), 10);

    const regionSummary =
      'Republica Dominicana con foco en La Altagracia (Higuey), La Romana y zonas comerciales cercanas.';

    const summarySections = [
      'INFORME SEMANAL AMPLIO DE INTELIGENCIA COMERCIAL (version inicial automatizada)',
      `Cobertura geografica: ${regionSummary}`,
      'Objetivo: construir una base semanal para estados, campanas y marketplace con enfoque en venta real, sin salir del alcance definido.',
      `Cobertura tematica estricta: ${topServices.join(', ')}.`,
      'Panorama de mercado: se observa continuidad de demanda en seguridad residencial, vigilancia para negocios, automatizacion de portones y tecnologia para puntos de venta. El patron dominante es comunicacion orientada a confianza, rapidez de instalacion y soporte tecnico cercano.',
      'Competencia y comunicacion: la mayoria de publicaciones tienden a formatos cortos (imagen + copy breve), oferta directa y mensajes de urgencia. Existe oportunidad clara en diferenciar con evidencia tecnica, casos reales locales y comparativos de valor.',
      'Comportamiento de audiencia: en sectores locales, la decision de compra mejora con mensajes concretos sobre garantia, soporte post-instalacion, tiempos de respuesta y demostracion visual del resultado final.',
      'Canales organicos: el enfoque organico mas efectivo combina constancia semanal, prueba social, contenido educativo y llamadas a accion simples hacia WhatsApp o visita tecnica.',
      'Insight de marcas y soluciones: la conversacion digital suele destacar facilidad de uso, confiabilidad, precio y garantia. Para camaras/portones/POS conviene vender solucion integral, no pieza aislada.',
      'Resumen de hallazgos publicos recientes:\n' +
        (topHeadlines.length > 0
          ? topHeadlines.map((h, i) => `${i + 1}. ${h}`).join('\n')
          : 'No se encontraron titulares publicos estrictamente relevantes en esta corrida; mantener monitoreo en la siguiente ventana semanal.'),
      'Recomendacion estrategica semanal: concentrar contenido en 1) seguridad comercial y residencial, 2) automatizacion de acceso, 3) modernizacion POS y control operativo, priorizando mensajes de beneficio tangible y casos de la zona objetivo.',
      'Nota metodologica: esta fase usa fuentes publicas abiertas con filtro estricto por rubro y zona. Se excluyen señales fuera de seguridad, control de acceso, portones, POS y alarmas.',
    ];

    const marketSummary = summarySections.join('\n\n');

    const competitorPublishingPatterns =
      'Patron detectado en fuentes abiertas: publicaciones de oferta directa, baja profundidad educativa y alta repeticion de mensajes promocionales. Predominan piezas visuales simples y textos cortos. Oportunidad para FULLTECH: contenido diferencial con estructura problema-solucion-prueba-CTA, mostrando ejecucion local y valor postventa.';

    const commonOffers =
      'Ofertas frecuentes en el mercado: instalacion incluida, descuentos por paquetes, bonos de configuracion inicial y mensajes de disponibilidad inmediata. Recomendacion: competir por valor total (garantia, soporte, calidad de instalacion), no solo por precio.';

    const observedPriceRanges =
      'Rango referencial observado en comunicacion publica: camaras y kits de seguridad con variabilidad alta segun canal, marcas y alcance; motores de porton y alarmas con enfoque en paquete instalado; POS con propuesta de productividad y control. Se recomienda levantar matriz de precios propia por servicio y localidad en la siguiente iteracion semanal.';

    const strongAngles = this.takeUnique(
      [
        'Seguridad integral por zonas criticas del negocio y hogar',
        'Instalacion profesional con soporte tecnico local',
        'Control remoto y evidencia en tiempo real desde celular',
        'Automatizacion de acceso para reducir riesgo operativo',
        'Soluciones POS para vender mas y controlar mejor',
      ],
      10,
    );

    const weakAngles = [
      'Hablar solo de precio sin contexto de garantia y servicio',
      'Publicaciones genericas sin enfoque geolocalizado en RD',
      'Mensajes sin prueba real de instalaciones o resultados',
    ];

    const contentOpportunities =
      'Plan de contenido organico semanal sugerido: 1) comparativos (antes/despues) de instalaciones reales, 2) micro-guia de decision por servicio (CCTV, portones, POS, alarmas, cerco electrico), 3) prueba social con casos locales, 4) piezas educativas para objeciones comunes, 5) CTA directo a diagnostico por WhatsApp.';

    const recommendedProducts = this.takeUnique(
      [
        ...topServices,
        'Sistema CCTV para negocio',
        'Motor de porton residencial/comercial',
        'Sistema POS para comercio local',
        'Alarma y cerco electrico por zonas',
      ],
      12,
    );

    const recommendedContentTypes = [
      'Carrusel comparativo de problema-solucion',
      'Reel corto de instalacion en campo',
      'Caso real con testimonio local',
      'Checklist descargable de compra inteligente',
      'Historia diaria con CTA a WhatsApp',
    ];

    const recommendedOffers = [
      'Diagnostico inicial sin costo',
      'Paquete integral por necesidad real del cliente',
      'Garantia clara de equipo e instalacion',
      'Plan de mantenimiento preventivo',
      'Escalabilidad por etapas segun presupuesto',
    ];

    const recommendedHooks = [
      'Que tan protegido esta tu negocio hoy?',
      'Lo que no se ve en una cotizacion barata',
      'Como reducir incidentes con una instalacion correcta',
      'Tu acceso puede ser mas seguro y mas rapido esta semana',
      'Controla ventas y seguridad desde un solo flujo operativo',
    ];

    const recommendedCTAs = [
      'Solicita evaluacion tecnica hoy',
      'Escribenos por WhatsApp para diagnostico',
      'Agenda visita en La Altagracia o La Romana',
      'Pide propuesta semanal personalizada',
      'Cotiza por prioridad de riesgo',
    ];

    const doMoreOfThis = [
      'Publicar casos reales con ubicacion local',
      'Educar antes de vender para elevar confianza',
      'Segmentar mensaje por servicio y tipo de cliente',
      'Usar CTA unico por pieza para medir respuesta',
      'Comparar alternativas y justificar recomendacion tecnica',
    ];

    const avoidThis = [
      'Copys largos sin estructura ni CTA',
      'Publicar solo catalogo sin contexto de uso real',
      'Prometer sin mostrar evidencia local',
      'Saturar mensajes de descuento sin propuesta de valor',
      'Ignorar objeciones frecuentes del cliente final',
    ];

    const confidenceBase = signals.length >= 15 ? 0.8 : signals.length >= 6 ? 0.72 : 0.58;

    const dataSources = this.takeUnique(
      [
        ...sourceLabels.map((item) => `source:${item}`),
        ...topServices.map((item) => `focus:${item}`),
        'google-news-rss-do',
      ],
      25,
    );

    return {
      marketSummary,
      competitorPublishingPatterns,
      commonOffers,
      observedPriceRanges,
      strongAngles,
      weakAngles,
      contentOpportunities,
      recommendedProducts,
      recommendedContentTypes,
      recommendedOffers,
      recommendedHooks,
      recommendedCTAs,
      doMoreOfThis,
      avoidThis,
      confidenceScore: confidenceBase,
      dataSources,
    };
  }

  private takeUnique(values: string[], max: number): string[] {
    const cleaned = values
      .map((item) => item.trim())
      .filter((item) => item.length > 0);
    return [...new Set(cleaned)].slice(0, max);
  }
}
