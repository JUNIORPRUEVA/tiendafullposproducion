import { Injectable } from '@nestjs/common';
import { MarketingStoryType } from '@prisma/client';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';

/**
 * PRIMARY source: products from the "Sistema de Vigilancia" catalog category.
 * These are the exact products FULLTECH sells and are the preferred base images.
 */
const PRIMARY_PRODUCT_KEYWORDS = ['sistema de vigilancia'];

/**
 * FALLBACK product keywords: if no "sistema de vigilancia" products have images,
 * fall back to other security-related categories.
 */
const FALLBACK_PRODUCT_KEYWORDS = [
  'seguridad',
  'camara',
  'cámara',
  'cctv',
  'nvr',
  'dvr',
  'alarma',
  'acceso',
  'videovigilancia',
  'sistema',
  'vigilancia',
];

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
};

@Injectable()
export class MarketingMediaSelectorService {
  private readonly publicBaseUrl: string;

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
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
    // Source 1 (PRIMARY): Productos de la categoria "Sistema de Vigilancia"
    const primaryProductRows = await this.prisma.product.findMany({
      where: {
        OR: PRIMARY_PRODUCT_KEYWORDS.map((kw) => ({
          categoria: { contains: kw, mode: 'insensitive' as const },
        })),
        imagen: { not: null },
      },
      select: { id: true, nombre: true, categoria: true, imagen: true },
      take: 40,
    });

    const primaryProductMedia: SelectedMedia[] = primaryProductRows
      .filter((p) => p.imagen && p.imagen.trim().length > 0)
      .map((p) => ({
        id: null,
        fileUrl: this.resolveImageUrl(p.imagen!),
        category: p.categoria,
        relatedService: p.nombre,
        tags: ['producto', 'sistema de vigilancia', 'seguridad', p.categoria.toLowerCase()],
        isFeatured: false,
        useCount: 0,
        sourceType: 'product-catalog-primary' as const,
      }));

    // Source 2 (SECONDARY): Galeria de Publicidad
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

    // Source 3 (FALLBACK): Other security product categories — only if primary is empty
    let fallbackProductMedia: SelectedMedia[] = [];
    if (primaryProductMedia.length === 0) {
      const fallbackRows = await this.prisma.product.findMany({
        where: {
          OR: FALLBACK_PRODUCT_KEYWORDS.map((kw) => ({
            categoria: { contains: kw, mode: 'insensitive' as const },
          })),
          imagen: { not: null },
          NOT: {
            OR: PRIMARY_PRODUCT_KEYWORDS.map((kw) => ({
              categoria: { contains: kw, mode: 'insensitive' as const },
            })),
          },
        },
        select: { id: true, nombre: true, categoria: true, imagen: true },
        take: 30,
      });

      fallbackProductMedia = fallbackRows
        .filter((p) => p.imagen && p.imagen.trim().length > 0)
        .map((p) => ({
          id: null,
          fileUrl: this.resolveImageUrl(p.imagen!),
          category: p.categoria,
          relatedService: p.nombre,
          tags: ['producto', 'seguridad', p.categoria.toLowerCase()],
          isFeatured: false,
          useCount: 0,
          sourceType: 'product-catalog-fallback' as const,
        }));
    }

    const allMedia = [...primaryProductMedia, ...galleryMedia, ...fallbackProductMedia];
    if (allMedia.length === 0) return null;

    const excluded = new Set(input.usedAssetIds);
    const product = input.recommendedProduct ? input.recommendedProduct.toLowerCase() : '';
    const service = input.recommendedService ? input.recommendedService.toLowerCase() : '';

    const nonRepeated = allMedia.filter((m) => m.id === null || !excluded.has(m.id));
    const pool = nonRepeated.length > 0 ? nonRepeated : allMedia;

    const candidates = pool
      .map((row) => ({ row, score: this.scoreAsset(row, input.type, product, service) }))
      .sort((a, b) => b.score - a.score);

    if (candidates.length === 0) return null;

    const top = candidates.slice(0, Math.min(3, candidates.length));
    const randomIndex = Math.floor(Math.random() * top.length);
    return top[randomIndex]?.row ?? candidates[0].row;
  }

  private resolveImageUrl(url: string): string {
    if (/^https?:\/\//i.test(url)) return url;
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
