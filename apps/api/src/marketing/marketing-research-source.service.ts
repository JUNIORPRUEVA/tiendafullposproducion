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
      label: 'Camaras de seguridad',
      query: 'camaras seguridad cctv instalacion',
      keywords: ['camara', 'cctv', 'videovigilancia', 'nvr', 'dvr', 'domo', 'bullet'],
    },
    {
      label: 'Motores de portones',
      query: 'motor porton electrico instalacion',
      keywords: ['porton', 'portones', 'motor de porton', 'automatizacion de porton'],
    },
    {
      label: 'Alarmas',
      query: 'alarma seguridad instalacion',
      keywords: ['alarma', 'alarmas', 'sensor', 'sirena'],
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
      query: 'sistema pos punto de venta negocio',
      keywords: ['pos', 'punto de venta', 'facturacion', 'caja', 'tpv', 'comercio'],
    },
    {
      label: 'Computadoras para negocios',
      query: 'computadoras para negocio caja inventario',
      keywords: ['computadora', 'pc', 'laptop', 'negocio', 'oficina'],
    },
    {
      label: 'Automatizacion comercial',
      query: 'automatizacion negocio control acceso',
      keywords: ['automatizacion', 'domotica', 'integracion', 'control'],
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

  private readonly salesKeywords = [
    'precio',
    'oferta',
    'promo',
    'promocion',
    'instalacion',
    'garantia',
    'cotiza',
    'whatsapp',
    'delivery',
    'cuota',
    'financiamiento',
    'combo',
    'paquete',
    'cliente',
    'negocio',
    'residencia',
  ];

  private readonly noiseKeywords = [
    'presidente',
    'ministerio',
    'senado',
    'camara de diputados',
    'partido politico',
    'congreso',
    'macroeconomia',
    'inflacion nacional',
    'banco central',
    'gobierno',
    'decreto',
    'tribunal',
    'licitacion publica',
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
    const platforms = [
      'facebook marketplace',
      'facebook ads',
      'instagram reels',
      'tiktok',
      'publicaciones comerciales',
      'anuncios locales',
    ];

    const queries: string[] = [];
    for (const topic of this.focusCatalog) {
      for (const platform of platforms) {
        for (const location of this.locations) {
          queries.push(`${topic.query} ${platform} ${location}`);
        }
      }
    }

    return [...new Set(queries)].slice(0, 36);
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
      return (
        this.matchesTopic(text) &&
        this.matchesLocation(text) &&
        this.isCommercialSignal(text) &&
        !this.isNoiseSignal(text)
      );
    });

    if (strict.length >= 8) {
      return strict.slice(0, 40);
    }

    const fallback = normalized.filter((signal) => {
      const text = `${signal.title} ${signal.source}`;
      return this.matchesTopic(text) && this.isCommercialSignal(text) && !this.isNoiseSignal(text);
    });

    return fallback.slice(0, 40);
  }

  private isCommercialSignal(text: string): boolean {
    const normalized = this.normalizeText(text);
    return this.salesKeywords.some((keyword) => normalized.includes(this.normalizeText(keyword)));
  }

  private isNoiseSignal(text: string): boolean {
    const normalized = this.normalizeText(text);
    return this.noiseKeywords.some((keyword) => normalized.includes(this.normalizeText(keyword)));
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
    const sourceLabels = this.takeUnique(
      signals.map((s) => s.source).filter((s) => s.length > 0),
      12,
    );
    const topHeadlines = this.takeUnique(signals.map((s) => s.title), 6);

    const marketSummaryLines = [
      'QUE ESTA FUNCIONANDO AHORA',
      '• Videos reales de instalacion y prueba en celular',
      '• Combos con instalacion incluida + garantia visible',
      '• Copy corto con beneficio directo y CTA a WhatsApp',
      '• Antes/despues y evidencias de negocios locales',
      '',
      'QUIEN ESTA COMPRANDO',
      '• Colmados, farmacias, repuestos y bancas',
      '• Tiendas pequenas y residencias nuevas',
      '• Negocios que necesitan controlar caja, acceso y camaras',
      '',
      'SENALES RECIENTES DETECTADAS',
      ...(topHeadlines.length === 0
        ? ['• Sin evidencia local suficiente en esta corrida. Mantener monitoreo corto.']
        : topHeadlines.map((headline) => `• ${headline}`)),
    ];

    const marketSummary = marketSummaryLines.join('\n');

    const competitorPublishingPatterns = [
      'PATRON DE COMPETIDORES LOCALES',
      '• Oferta directa, texto corto y urgencia',
      '• Menos enfoque en prueba tecnica real',
      '• Mucho precio, poca explicacion de valor',
      '• Oportunidad FULLTECH: evidencia + confianza + CTA claro',
    ].join('\n');

    const commonOffers = [
      'OFERTAS QUE RESPONDEN MAS',
      '• Instalacion incluida',
      '• Descuento por combo',
      '• Delivery o visita tecnica rapida',
      '• Garantia 1 ano visible',
      '• Pago por cuotas o facilidades',
    ].join('\n');

    const observedPriceRanges = [
      'RANGOS Y PAQUETES BUSCADOS',
      '• El cliente responde mejor a paquetes, no piezas sueltas',
      '• CCTV y portones: decision por valor total + instalacion',
      '• POS/computadoras: compran por control y productividad',
      '• Recomendacion: publicar 3 paquetes (basico, pro, negocio)',
    ].join('\n');

    const strongAngles = this.takeUnique(
      [
        'Protege tu negocio desde el celular hoy',
        'Instalacion real en Higuey con soporte local rapido',
        'Combos seguridad + instalacion + garantia',
        'Control de acceso y camaras para reducir perdidas',
        'POS y computadoras para vender mas y controlar inventario',
      ],
      10,
    );

    const weakAngles = [
      'Copys largos y genericos',
      'Hablar de tecnologia sin beneficio de venta',
      'Publicar sin CTA directo a WhatsApp',
      'Mostrar solo precio sin garantia ni instalacion',
    ];

    const contentOpportunities = [
      'CONTENIDO RECOMENDADO HOY',
      'Estado recomendado: Protege tu negocio desde tu celular. Instalacion rapida en Higuey. Escribenos ahora.',
      'Idea de video: tecnico instalando + camara funcionando + vista celular + cliente validando grabacion.',
      'Formato: Reel vertical 20-35s con subtitulos grandes.',
      'Visual: colores de contraste alto y sello de garantia.',
    ].join('\n');

    const recommendedProducts = this.takeUnique(
      [
        ...topServices,
        'Combo camaras + instalacion',
        'Motor de porton residencial',
        'Kit alarma + cerco electrico',
        'POS + computadora para negocio',
      ],
      12,
    );

    const recommendedContentTypes = [
      'Reel corto vertical 20-35s',
      'Video de instalacion real',
      'Antes y despues de proyecto',
      'Testimonio real breve',
      'Imagen del equipo ya instalado',
    ];

    const recommendedOffers = [
      'Instalacion incluida',
      'Garantia visible en pieza',
      'Combo con descuento',
      'Visita tecnica rapida',
      'Facilidad de pago',
    ];

    const recommendedHooks = [
      'Tu negocio esta protegido de verdad?',
      'Mira como queda instalado en minutos',
      'Evita perdidas con control desde tu celular',
      'Combo listo para negocio pequeno',
      'Seguridad + soporte local sin complicarte',
    ];

    const recommendedCTAs = [
      'Escribenos por WhatsApp ahora',
      'Cotiza hoy y agenda instalacion',
      'Pide tu combo recomendado',
      'Solicita visita tecnica en Higuey',
      'Pregunta por facilidades de pago',
    ];

    const doMoreOfThis = [
      'Publicar evidencia real local todas las semanas',
      'Usar CTA unico y medible por pieza',
      'Responder objeciones en video corto',
      'Mostrar garantia e instalacion desde el inicio',
      'Segmentar por negocio pequeno y residencia',
    ];

    const avoidThis = [
      'Noticias nacionales y contenido politico',
      'Parrafos largos sin accion',
      'Promociones sin prueba visual',
      'Mensajes institucionales sin venta',
      'Publicar sin enfocar mercado local',
    ];

    const confidenceBase = signals.length >= 15 ? 0.86 : signals.length >= 6 ? 0.76 : 0.64;

    const dataSources = this.takeUnique(
      [
        ...sourceLabels.map((item) => `source:${item}`),
        ...topServices.map((item) => `focus:${item}`),
        'scope:ventas-publicidad-local',
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
