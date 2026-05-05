import { Injectable } from '@nestjs/common';
import { MarketingStoryType } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

type SelectorInput = {
  companyId: string;
  type: MarketingStoryType;
  recommendedService?: string | null;
  recommendedProduct?: string | null;
  usedAssetIds: string[];
};

@Injectable()
export class MarketingMediaSelectorService {
  constructor(private readonly prisma: PrismaService) {}

  async select(input: SelectorInput) {
    const rows = await this.prisma.marketingMediaAsset.findMany({
      where: {
        companyId: input.companyId,
        isActive: true,
      },
      orderBy: [{ isFeatured: 'desc' }, { useCount: 'asc' }, { createdAt: 'desc' }],
      take: 80,
    });

    if (rows.length === 0) return null;

    const excluded = new Set(input.usedAssetIds);
    const product = `${input.recommendedProduct ?? ''}`.toLowerCase();
    const service = `${input.recommendedService ?? ''}`.toLowerCase();

    const candidates = rows
      .filter((row) => !excluded.has(row.id) || rows.length <= input.usedAssetIds.length + 1)
      .map((row) => ({ row, score: this.scoreAsset(row, input.type, product, service) }))
      .sort((a, b) => b.score - a.score);

    return candidates[0]?.row ?? null;
  }

  private scoreAsset(
    row: {
      category: string;
      relatedService: string | null;
      tags: unknown;
      isFeatured: boolean;
      useCount: number;
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
    if (row.isFeatured) score += 40;
    score += Math.max(0, 30 - row.useCount * 2);

    if (recommendedService && relatedService.includes(recommendedService)) score += 30;
    if (recommendedProduct && relatedService.includes(recommendedProduct)) score += 30;

    if (recommendedService && category.includes(recommendedService)) score += 25;
    if (recommendedProduct && category.includes(recommendedProduct)) score += 25;

    if (tags.some((tag) => recommendedService && tag.includes(recommendedService))) score += 20;
    if (tags.some((tag) => recommendedProduct && tag.includes(recommendedProduct))) score += 20;

    if (type === 'SALES') {
      if (this.contains(category, ['motor', 'porton']) && this.matchesAny(recommendedProduct, recommendedService, ['motor', 'porton'])) score += 35;
      if (this.contains(category, ['camara']) && this.matchesAny(recommendedProduct, recommendedService, ['camara', 'seguridad'])) score += 35;
      if (this.contains(category, ['pos']) && this.matchesAny(recommendedProduct, recommendedService, ['pos'])) score += 30;
    }

    if (type === 'TRUST') {
      if (this.contains(category, ['equipo tecnico', 'tienda', 'cliente', 'trabajo'])) score += 35;
      if (this.contains(category, ['instalacion'])) score += 20;
    }

    if (type === 'EDUCATIONAL') {
      if (this.contains(category, ['instalacion', 'tecnologia', 'camara', 'motor', 'pos'])) score += 22;
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
