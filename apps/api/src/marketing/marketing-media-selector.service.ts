import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { MarketingStoryType } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

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
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  async select(input: SelectorInput): Promise<SelectedMedia | null> {
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
    const usedUrls = new Set(input.usedFileUrls ?? []);
    const product = input.recommendedProduct ? input.recommendedProduct.toLowerCase() : '';
    const service = input.recommendedService ? input.recommendedService.toLowerCase() : '';

    const nonRepeated = galleryMedia.filter(
      (m) => (m.id === null || !excluded.has(m.id)) && !usedUrls.has(m.fileUrl),
    );
    const pool = nonRepeated.length > 0 ? nonRepeated : galleryMedia;

    if (pool.length > 0 && (input.imagePrompt || input.copyText)) {
      const smartIdx = await this.smartPickGalleryAsset(
        pool,
        input.imagePrompt ?? '',
        input.copyText ?? '',
      );
      if (smartIdx !== null) {
        return pool[smartIdx];
      }
    }

    const candidates = pool
      .map((row) => ({ row, score: this.scoreAsset(row, input.type, product, service) }))
      .sort((a, b) => b.score - a.score);

    if (candidates.length === 0) return null;

    const top = candidates.slice(0, Math.min(3, candidates.length));
    const randomIndex = Math.floor(Math.random() * top.length);
    return top[randomIndex]?.row ?? candidates[0].row;
  }

  private async smartPickGalleryAsset(
    galleryPool: SelectedMedia[],
    imagePrompt: string,
    copyText: string,
  ): Promise<number | null> {
    const openaiKey =
      this.config.get<string>('OPENAI_API_KEY') ?? process.env.OPENAI_API_KEY ?? '';
    if (!openaiKey || galleryPool.length === 0) return null;

    const assetList = galleryPool
      .map((asset, index) => {
        const tags = Array.isArray(asset.tags)
          ? asset.tags.map((item) => String(item).trim()).filter((item) => item.length > 0)
          : [];
        return `${index}: nombre="${asset.relatedService ?? 'Sin nombre'}" categoria="${asset.category}" tags="${tags.join(', ')}" destacada=${asset.isFeatured ? 'si' : 'no'}`;
      })
      .join('\n');

    const userMessage =
      `Eres un selector de imagen base para anuncios de marketing. Debes elegir una sola imagen desde la galería interna de publicidad.\n\n` +
      `Prompt visual del anuncio:\n"${imagePrompt}"\n\n` +
      `Texto/copy del anuncio:\n"${copyText}"\n\n` +
      `Galería disponible:\n${assetList}\n\n` +
      `Responde SOLO con el número del índice de la imagen más relevante. Sin explicación.`;

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
      if (!isNaN(idx) && idx >= 0 && idx < galleryPool.length) {
        return idx;
      }
      return null;
    } catch {
      return null;
    }
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
