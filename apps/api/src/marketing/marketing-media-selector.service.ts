import { Injectable } from '@nestjs/common';
import { MarketingStoryType } from '@prisma/client';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';

/** Keywords used to filter products from the security-systems catalog */
const SECURITY_CATEGORY_KEYWORDS = [
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
  sourceType: 'gallery' | 'product-catalog';
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
    // ── Source 1: Galería de Publicidad ──────────────────────────────────────
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

    // ── Source 2: Catálogo de productos — categoría sistema de seguridad ─────
    const productRows = await this.prisma.product.findMany({
      where: {
        OR: SECURITY_CATEGORY_KEYWORDS.map((kw) => ({
          categoria: { contains: kw, mode: 'insensitive' as const },
        })),
        imagen: { not: null },
      },
      select: { id: true, nombre: true, categoria: true, imagen: true },
      take: 40,
    });

    const productMedia: SelectedMedia[] = productRows
      .filter((p) => p.imagen && p.imagen.trim().length > 0)
      .map((p) => ({
        id: null,
        fileUrl: this.resolveImageUrl(p.imagen!),
        category: p.categoria,
        relatedService: p.nombre,
        tags: ['producto', 'seguridad', p.categoria.toLowerCase()],
        isFeatured: false,
        useCount: 0,
        sourceType: 'product-catalog' as const,
      }));

    // ── Merge + score ─────────────────────────────────────────────────────────
    const allMedia = [...galleryMedia, ...productMedia];
    if (allMedia.length === 0) return null;

    const excluded = new Set(input.usedAssetIds);
    const product = `${input.recommendedProduct ?? ''}`.toLowerCase();
    const service = `${input.recommendedService ?? ''}`.toLowerCase();

    // Exclude already-used gallery assets (product items have id=null so they
    // are never considered "excluded" by asset ID)
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

  /** Resolve relative product image paths to full absolute URLs */
  private resolveImageUrl(url: string): string {
    if (/^https?:\/\//i.test(url)) return url;
    const normalized = url.startsWith('/') ? url : `/${url}`;
    return `${this.publicBaseUrl}${normalized}`;
  }

  private scoreAsset(
    row: {
      category: string;
      relatedService: string | null;
      tags: unknown;
      isFeatured: boolean;
      useCount: number;
      sourceType: 'gallery' | 'product-catalog';
    },
    type: MarketingStoryType,
    recommendedProduct: string,
    recommendedService: string,
  ) {
    const category = row.category.toLowerCase();
    const relatedService = `${row.relatedService ?? ''}`.toLowerCase();
    const tags = Array.isArray(row.tags)
      ? row.tags.map((item) => `${item}`.toLowerCase())
      : [];

    let score = 0;

    // Gallery assets get a modest priority bonus (curated content)
    if (row.sourceType === 'gallery') score += 15;
    if (row.isFeatured) score += 40;
    score += Math.max(0, 30 - row.useCount * 2);

    if (recommendedService && relatedService.includes(recommendedService)) score += 30;
    if (recommendedProduct && relatedService.includes(recommendedProduct)) score += 30;

    if (recommendedService && category.includes(recommendedService)) score += 25;
    if (recommendedProduct && category.includes(recommendedProduct)) score += 25;

    if (tags.some((tag) => recommendedService && tag.includes(recommendedService))) score += 20;
    if (tags.some((tag) => recommendedProduct && tag.includes(recommendedProduct))) score += 20;

    if (type === 'SALES') {
      if (this.contains(category, ['promo', 'oferta', 'producto', 'combos'])) score += 26;
      if (tags.some((tag) => this.contains(tag, ['promo', 'oferta', 'precio', 'descuento']))) score += 20;
      if (
        this.contains(category, ['motor', 'porton']) &&
        this.matchesAny(recommendedProduct, recommendedService, ['motor', 'porton'])
      )
        score += 35;
      if (
        this.contains(category, ['camara', 'cámara', 'cctv', 'seguridad']) &&
        this.matchesAny(recommendedProduct, recommendedService, ['camara', 'seguridad', 'cctv'])
      )
        score += 35;
      if (this.contains(category, ['pos']) && this.matchesAny(recommendedProduct, recommendedService, ['pos']))
        score += 30;
    }

    if (type === 'TRUST') {
      if (tags.some((tag) => this.contains(tag, ['real', 'cliente', 'instalado', 'equipo']))) score += 24;
      if (this.contains(category, ['equipo tecnico', 'tienda', 'cliente', 'trabajo'])) score += 35;
      if (this.contains(category, ['instalacion'])) score += 20;
    }

    if (type === 'EDUCATIONAL') {
      if (tags.some((tag) => this.contains(tag, ['simple', 'limpio', 'minimal', 'espacio']))) score += 20;
      if (this.contains(category, ['instalacion', 'tecnologia', 'camara', 'cámara', 'motor', 'pos', 'cctv', 'sistema']))
        score += 22;
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
