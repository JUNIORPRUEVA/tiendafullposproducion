import { Injectable, Logger } from '@nestjs/common';
import { MarketingStoryType } from '@prisma/client';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import { CatalogProductsService } from '../products/catalog-products.service';

/**
 * Product NAME keywords to identify cameras, DVRs, NVRs, and gate motors.
 * These match against the `nombre` field of each FullPOS catalog product.
 * The FullPOS integration API does NOT return category data (all null), so
 * name-based filtering is the only reliable way to identify security products.
 */
const SECURITY_PRODUCT_NAME_KEYWORDS = [
  'camara', 'cámara', 'camera', 'cam ',
  'dvr', 'nvr', 'cctv',
  'motor', 'porton', 'portón',
  'domo', 'bullet', 'bala',
  'hikvision', 'dahua', 'hilook', 'epcom', 'reolink', 'imou', 'unv',
  'vigilancia', '4mp', '8mp', '2mp', '5mp',
  'turbo hd', 'hd poe', ' poe',
  'videoportero',
];

/** Placeholder image hosts that should be excluded (not real product photos) */
const PLACEHOLDER_IMAGE_HOSTS = ['images.unsplash.com', 'picsum.photos', 'placehold.it'];

export type SelectedMedia = {
  /** marketingMediaAsset.id for gallery items; null for product-catalog items */
  id: string | null;
  fileUrl: string;
  category: string;
  relatedService: string | null;
  tags: unknown;
  isFeatured: boolean;
  useCount: number;
  /** Where the image came from */
  sourceType: 'gallery' | 'product-catalog-primary' | 'product-catalog-fallback';
};

type SelectorInput = {
  companyId: string;
  type: MarketingStoryType;
  recommendedService?: string | null;
  recommendedProduct?: string | null;
  usedAssetIds: string[];
  /** fileUrls already used in other stories today — prevents repeating the same product image */
  usedFileUrls?: string[];
  /** Visual description of what the AI image should show — used to smart-match catalog products */
  imagePrompt?: string | null;
  /** Copy text of the story — used as additional context for product matching */
  copyText?: string | null;
};

@Injectable()
export class MarketingMediaSelectorService {
  private readonly logger = new Logger(MarketingMediaSelectorService.name);
  private readonly publicBaseUrl: string;

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly catalogProducts: CatalogProductsService,
  ) {
    this.publicBaseUrl = (
      this.config.get<string>('PUBLIC_BASE_URL') ??
      this.config.get<string>('API_BASE_URL') ??
      process.env.PUBLIC_BASE_URL ??
      process.env.API_BASE_URL ??
      'http://localhost:4000'
    )
      .trim()
      .replace(/\/$/, '');
  }

  async select(input: SelectorInput): Promise<SelectedMedia | null> {
    // Load full product catalog from FullPOS (source of truth for FULLTECH products)
    let catalogItems: { id: string; nombre: string; categoria: string | null; categoriaNombre: string | null; imagen: string | null; fotoUrl: string | null }[] = [];
    try {
      const catalog = await this.catalogProducts.findAll();
      catalogItems = catalog.items;
      this.logger.log(`[media-selector] catalog loaded: ${catalogItems.length} products total`);
    } catch (err) {
      this.logger.warn(`[media-selector] catalog unavailable: ${err instanceof Error ? err.message : String(err)}`);
    }

    const isSecurityProduct = (nombre: string): boolean => {
      const n = nombre.toLowerCase();
      return SECURITY_PRODUCT_NAME_KEYWORDS.some((kw) => n.includes(kw));
    };

    const isPlaceholderImage = (url: string): boolean => {
      try {
        const host = new URL(url).hostname;
        return PLACEHOLDER_IMAGE_HOSTS.some((ph) => host.includes(ph));
      } catch {
        return false;
      }
    };

    // Security products: cameras, DVRs, NVRs, motors — identified by product name only.
    // The FullPOS integration API does not return category data, so name matching is the
    // only reliable filter. Placeholder images (e.g. Unsplash) are excluded.
    const securityProductMedia: SelectedMedia[] = catalogItems
      .filter((p) => {
        const imgUrl = p.fotoUrl ?? p.imagen ?? '';
        return (
          isSecurityProduct(p.nombre) &&
          imgUrl.trim().length > 0 &&
          !isPlaceholderImage(imgUrl)
        );
      })
      .map((p) => {
        const imgUrl = p.fotoUrl ?? p.imagen ?? '';
        return {
          id: null,
          fileUrl: imgUrl,
          category: 'Sistema de Vigilancia',
          relatedService: p.nombre,
          tags: ['producto', 'seguridad', 'vigilancia'],
          isFeatured: false,
          useCount: 0,
          sourceType: 'product-catalog-primary' as const,
        };
      });

    this.logger.log(
      `[media-selector] security products with real image: ${securityProductMedia.length} / ${catalogItems.length} total`,
    );

    // Exclude already-used image URLs to ensure variety across stories
    const usedUrls = new Set(input.usedFileUrls ?? []);
    const unusedSecurityMedia = securityProductMedia.filter((p) => !usedUrls.has(p.fileUrl));
    const securityPool =
      unusedSecurityMedia.length > 0 ? unusedSecurityMedia : securityProductMedia;

    // If security products exist, use them exclusively (no gallery fallback)
    if (securityPool.length > 0) {
      if (input.imagePrompt || input.copyText) {
        const smartIdx = await this.smartPickProduct(
          securityPool,
          input.imagePrompt ?? '',
          input.copyText ?? '',
        );
        if (smartIdx !== null) {
          const picked = securityPool[smartIdx];
          this.logger.log(
            `[media-selector] GPT picked: "${picked.relatedService}" (index=${smartIdx}, pool=${securityPool.length}, unused=${unusedSecurityMedia.length})`,
          );
          return picked;
        }
      }
      // GPT unavailable or no prompt — pick first unused
      const picked = securityPool[0];
      this.logger.log(
        `[media-selector] fallback pick: "${picked.relatedService}" (pool=${securityPool.length})`,
      );
      return picked;
    }

    // No catalog security products available — fall back to gallery
    this.logger.warn(`[media-selector] no security products with images found — using gallery`);

    const galleryRows = await this.prisma.marketingMediaAsset.findMany({
      where: { companyId: input.companyId, isActive: true },
      orderBy: [{ isFeatured: 'desc' }, { useCount: 'asc' }, { createdAt: 'desc' }],
      take: 80,
    });

    const galleryMedia: SelectedMedia[] = galleryRows.map((row) => ({
      id: row.id,
      fileUrl: row.fileUrl,
      category: row.category,
      relatedService: row.relatedService,
      tags: row.tags,
      isFeatured: row.isFeatured,
      useCount: row.useCount,
      sourceType: 'gallery' as const,
    }));

    if (galleryMedia.length === 0) return null;

    const excluded = new Set(input.usedAssetIds);
    const product = input.recommendedProduct ? input.recommendedProduct.toLowerCase() : '';
    const service = input.recommendedService ? input.recommendedService.toLowerCase() : '';

    const nonRepeated = galleryMedia.filter((m) => m.id === null || !excluded.has(m.id));
    const pool = nonRepeated.length > 0 ? nonRepeated : galleryMedia;

    const candidates = pool
      .map((row) => ({ row, score: this.scoreAsset(row, input.type, product, service) }))
      .sort((a, b) => b.score - a.score);

    if (candidates.length === 0) return null;

    const top = candidates.slice(0, Math.min(3, candidates.length));
    const randomIndex = Math.floor(Math.random() * top.length);
    return top[randomIndex]?.row ?? candidates[0].row;
  }

  /**
   * Uses GPT-4o-mini to intelligently match a catalog product to the story's visual prompt.
   * Sends a lightweight text request asking which product best represents the desired image.
   * Returns the index into `catalogPool`, or null if the call fails or returns an invalid result.
   */
  private async smartPickProduct(
    catalogPool: SelectedMedia[],
    imagePrompt: string,
    copyText: string,
  ): Promise<number | null> {
    const openaiKey =
      this.config.get<string>('OPENAI_API_KEY') ?? process.env.OPENAI_API_KEY ?? '';
    if (!openaiKey || catalogPool.length === 0) return null;

    // Build a compact product list (name + category) for the model
    const productList = catalogPool
      .map(
        (p, i) =>
          `${i}: "${p.relatedService ?? 'Producto'}" (categoría: ${p.category || 'Sin categoría'})`,
      )
      .join('\n');

    const userMessage =
      `Eres un selector de imágenes para anuncios de marketing. Tu única tarea es elegir qué producto del catálogo serviría mejor como IMAGEN BASE para el diseño del anuncio.\n\n` +
      `Descripción visual del anuncio:\n"${imagePrompt}"\n\n` +
      `Texto del anuncio:\n"${copyText}"\n\n` +
      `Productos disponibles (índice: nombre - categoría):\n${productList}\n\n` +
      `Responde SOLO con el número del índice del producto más relevante. Sin explicación, solo el número.`;

    try {
      const response = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${openaiKey}`,
        },
        body: JSON.stringify({
          model: 'gpt-4o-mini',
          messages: [{ role: 'user', content: userMessage }],
          max_tokens: 5,
          temperature: 0,
        }),
      });

      if (!response.ok) return null;

      const data = (await response.json()) as {
        choices?: Array<{ message?: { content?: string } }>;
      };
      const text = (data.choices?.[0]?.message?.content ?? '').trim();
      const idx = parseInt(text, 10);
      if (!isNaN(idx) && idx >= 0 && idx < catalogPool.length) return idx;
      return null;
    } catch {
      return null;
    }
  }

  private resolveImageUrl(url: string): string {
    const normalized = url.startsWith('/') ? url : '/' + url;
    return this.publicBaseUrl + normalized;
  }

  private scoreAsset(
    row: {
      category: string;
      relatedService: string | null;
      tags: unknown;
      isFeatured: boolean;
      useCount: number;
      sourceType: 'gallery' | 'product-catalog-primary' | 'product-catalog-fallback';
    },
    type: MarketingStoryType,
    recommendedProduct: string,
    recommendedService: string,
  ) {
    const category = row.category.toLowerCase();
    const relatedService = (row.relatedService ?? '').toLowerCase();
    const tags = Array.isArray(row.tags) ? row.tags.map((item) => String(item).toLowerCase()) : [];

    let score = 0;

    // Source-type bonuses
    if (row.sourceType === 'product-catalog-primary') {
      score += 35; // "Sistema de Vigilancia" products = highest priority
    } else if (row.sourceType === 'gallery') {
      score += 10; // Galeria de Publicidad = secondary
      if (row.isFeatured) score += 40;
      score += Math.max(0, 30 - row.useCount * 2);
    }
    // fallback catalog: no source bonus

    // Relevance scoring
    if (recommendedService && relatedService.includes(recommendedService)) score += 30;
    if (recommendedProduct && relatedService.includes(recommendedProduct)) score += 30;
    if (recommendedService && category.includes(recommendedService)) score += 25;
    if (recommendedProduct && category.includes(recommendedProduct)) score += 25;
    if (tags.some((tag) => recommendedService && tag.includes(recommendedService))) score += 20;
    if (tags.some((tag) => recommendedProduct && tag.includes(recommendedProduct))) score += 20;

    // Story-type specific scoring
    if (type === 'SALES') {
      if (this.contains(category, ['promo', 'oferta', 'producto', 'combos'])) score += 26;
      if (tags.some((tag) => this.contains(tag, ['promo', 'oferta', 'precio', 'descuento']))) score += 20;
      if (this.contains(category, ['motor', 'porton']) && this.matchesAny(recommendedProduct, recommendedService, ['motor', 'porton'])) score += 35;
      if (this.contains(category, ['camara', 'cámara', 'cctv', 'seguridad', 'vigilancia']) && this.matchesAny(recommendedProduct, recommendedService, ['camara', 'seguridad', 'cctv', 'vigilancia'])) score += 35;
      if (this.contains(category, ['pos']) && this.matchesAny(recommendedProduct, recommendedService, ['pos'])) score += 30;
    }

    if (type === 'TRUST') {
      if (tags.some((tag) => this.contains(tag, ['real', 'cliente', 'instalado', 'equipo']))) score += 24;
      if (this.contains(category, ['equipo tecnico', 'tienda', 'cliente', 'trabajo'])) score += 35;
      if (this.contains(category, ['instalacion', 'vigilancia', 'seguridad'])) score += 20;
    }

    if (type === 'EDUCATIONAL') {
      if (tags.some((tag) => this.contains(tag, ['simple', 'limpio', 'minimal', 'espacio']))) score += 20;
      if (this.contains(category, ['instalacion', 'tecnologia', 'camara', 'cámara', 'motor', 'pos', 'cctv', 'sistema', 'vigilancia'])) score += 22;
      if (tags.some((tag) => this.contains(tag, ['limpio', 'espacio', 'texto', 'clean']))) score += 18;
    }

    return score;
  }

  private contains(value: string, keys: string[]) {
    return keys.some((key) => value.includes(key));
  }

  private matchesAny(product: string, service: string, keys: string[]) {
    return keys.some((key) => product.includes(key) || service.includes(key));
  }
}
