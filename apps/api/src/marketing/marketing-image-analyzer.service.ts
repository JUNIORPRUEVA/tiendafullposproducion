import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

export interface ImageAnalysisResult {
  mediaAssetId: string;
  fileUrl: string;
  category: string;
  productType: string;
  visualQuality: 'excellent' | 'good' | 'acceptable' | 'poor';
  qualityScore: number; // 0-100
  recommendation: string;
  recommendationReason: string[];
  bestForStoryTypes: ('sales' | 'trust' | 'educational')[];
  estimatedConversionLift: number; // percentage
  suggestedAngle: string;
  lightingQuality: 'professional' | 'good' | 'acceptable' | 'needs_improvement';
  productClarityScore: number; // 0-100
  backgroundQuality: 'professional' | 'acceptable' | 'distracting';
  usageHistory: {
    timesUsed: number;
    lastUsedAt: Date | null;
    conversionMetrics: {
      impressions: number;
      clicks: number;
      conversions: number;
    };
  };
}

@Injectable()
export class MarketingImageAnalyzerService {
  constructor(private prisma: PrismaService) {}

  /**
   * Analyzes a single media asset and provides AI recommendations
   */
  async analyzeMediaAsset(
    mediaAssetId: string,
    companyId: string,
  ): Promise<ImageAnalysisResult> {
    const asset = await this.prisma.marketingMediaAsset.findUnique({
      where: { id: mediaAssetId },
    });

    if (!asset) {
      throw new Error(`Media asset not found: ${mediaAssetId}`);
    }

    // Validate asset belongs to company
    if (asset.companyId !== companyId) {
      throw new Error('Unauthorized access to media asset');
    }

    const qualityScore = this._calculateQualityScore(asset);
    const bestStoryTypes = this._determineBestStoryTypes(asset, qualityScore);
    const recommendation = this._generateRecommendation(asset, bestStoryTypes);
    const reasons = this._generateRecommendationReasons(
      asset,
      qualityScore,
      bestStoryTypes,
    );

    const conversions = 0;

    return {
      mediaAssetId: asset.id,
      fileUrl: asset.fileUrl,
      category: asset.category || 'Uncategorized',
      productType: asset.relatedService || 'General',
      visualQuality: this._classifyQuality(qualityScore),
      qualityScore,
      recommendation,
      recommendationReason: reasons,
      bestForStoryTypes: bestStoryTypes,
      estimatedConversionLift: this._estimateConversionLift(
        asset,
        bestStoryTypes,
      ),
      suggestedAngle: this._suggestContentAngle(asset),
      lightingQuality: this._assessLighting(asset),
      productClarityScore: this._assessProductClarity(asset),
      backgroundQuality: this._assessBackground(asset),
      usageHistory: {
        timesUsed: asset.useCount || 0,
        lastUsedAt: asset.lastUsedAt || null,
        conversionMetrics: {
          impressions: 0,
          clicks: 0,
          conversions,
        },
      },
    };
  }

  /**
   * Analyzes multiple assets and ranks them by suitability
   */
  async rankMediaAssets(
    mediaAssetIds: string[],
    storyType: 'sales' | 'trust' | 'educational',
    companyId: string,
  ): Promise<ImageAnalysisResult[]> {
    const analyses = await Promise.all(
      mediaAssetIds.map((id) => this.analyzeMediaAsset(id, companyId)),
    );

    // Rank by relevance to story type and quality
    return analyses.sort((a, b) => {
      const aScore = a.bestForStoryTypes.includes(storyType)
        ? a.qualityScore + 20
        : a.qualityScore;
      const bScore = b.bestForStoryTypes.includes(storyType)
        ? b.qualityScore + 20
        : b.qualityScore;

      return bScore - aScore;
    });
  }

  // ============================================
  // Private Analysis Methods
  // ============================================

  private _calculateQualityScore(asset: any): number {
    let score = 50; // Base score

    // Lighting bonus
    if (asset.lightingQuality === 'professional') score += 20;
    else if (asset.lightingQuality === 'good') score += 12;
    else if (asset.lightingQuality === 'acceptable') score += 5;

    // Product clarity bonus
    if (asset.productClarityScore >= 85) score += 15;
    else if (asset.productClarityScore >= 70) score += 10;
    else if (asset.productClarityScore >= 55) score += 5;

    // Background quality bonus
    if (asset.backgroundQuality === 'professional') score += 10;
    else if (asset.backgroundQuality === 'acceptable') score += 5;

    // Recent usage bonus (not too old)
    if (asset.useCount && asset.useCount > 0) {
      const daysOld = Math.floor(
        (Date.now() - (asset.lastUsedAt?.getTime() || 0)) / (1000 * 60 * 60 * 24),
      );
      if (daysOld < 7) score += 8;
      else if (daysOld > 90) score -= 5;
    }

    // Featured bonus
    if (asset.isFeatured) score += 5;

    // Ensure score is in 0-100 range
    return Math.max(0, Math.min(100, score));
  }

  private _classifyQuality(
    score: number,
  ): 'excellent' | 'good' | 'acceptable' | 'poor' {
    if (score >= 85) return 'excellent';
    if (score >= 70) return 'good';
    if (score >= 55) return 'acceptable';
    return 'poor';
  }

  private _determineBestStoryTypes(
    asset: any,
    qualityScore: number,
  ): ('sales' | 'trust' | 'educational')[] {
    const types: ('sales' | 'trust' | 'educational')[] = [];

    // High quality → trust/sales
    if (qualityScore >= 75) {
      types.push('trust', 'sales');
    } else if (qualityScore >= 60) {
      types.push('sales');
    }

    // Educational usually works with any decent image
    if (qualityScore >= 55) {
      types.push('educational');
    }

    return types.length > 0 ? types : ['sales']; // Default to sales
  }

  private _generateRecommendation(
    asset: any,
    bestTypes: string[],
  ): string {
    if (bestTypes.includes('trust') && bestTypes.includes('sales')) {
      return 'Excelente para confianza y ventas. Imagen premium.';
    }
    if (bestTypes.includes('trust')) {
      return 'Ideal para construir confianza. Alta calidad visual.';
    }
    if (bestTypes.includes('sales')) {
      return 'Buena opción para conversión. Producto claro.';
    }
    return 'Adecuada para contenido educativo.';
  }

  private _generateRecommendationReasons(
    asset: any,
    qualityScore: number,
    bestTypes: string[],
  ): string[] {
    const reasons: string[] = [];

    if (qualityScore >= 85) {
      reasons.push('Iluminación profesional');
      reasons.push('Composición clara');
    } else if (qualityScore >= 70) {
      reasons.push('Buena iluminación');
      reasons.push('Producto visible');
    }

    if (asset.isFeatured) {
      reasons.push('Marcada como destacada');
    }

    if (asset.useCount && asset.useCount > 5) {
      reasons.push('Probada con usuarios');
    }

    if (bestTypes.includes('trust')) {
      reasons.push('Alto impacto en confianza');
    }

    if (bestTypes.includes('sales')) {
      reasons.push('Optimizada para conversión');
    }

    return reasons.length > 0 ? reasons : ['Imagen disponible'];
  }

  private _estimateConversionLift(
    asset: any,
    bestTypes: string[],
  ): number {
    let lift = 5; // Base 5% lift

    // Award points for matching story types
    if (bestTypes.includes('sales')) lift += 8;
    if (bestTypes.includes('trust')) lift += 12;

    // Reduce lift if high usage (potential fatigue)
    if (asset.useCount && asset.useCount > 20) {
      lift -= 3;
    }

    // Boost if featured
    if (asset.isFeatured) lift += 3;

    return lift;
  }

  private _suggestContentAngle(asset: any): string {
    const service = asset.relatedService?.toLowerCase() || '';

    if (
      service.includes('camara') ||
      service.includes('surveillance') ||
      service.includes('hikvision')
    ) {
      return 'Enfoque en seguridad y vigilancia profesional';
    }

    if (service.includes('motor') || service.includes('motor')) {
      return 'Enfoque en automatización y control';
    }

    if (service.includes('cerco') || service.includes('fence')) {
      return 'Enfoque en protección perimetral';
    }

    if (service.includes('pos') || service.includes('payment')) {
      return 'Enfoque en modernización comercial';
    }

    if (service.includes('computer') || service.includes('pc')) {
      return 'Enfoque en productividad y rendimiento';
    }

    return 'Enfoque en soluciones comerciales';
  }

  private _assessLighting(asset: any): 'professional' | 'good' | 'acceptable' | 'needs_improvement' {
    // This would ideally use computer vision API or stored metadata
    // For now, based on usage patterns
    if (asset.isFeatured && asset.useCount > 10) return 'professional';
    if (asset.useCount > 5) return 'good';
    if (asset.useCount > 0) return 'acceptable';
    return 'needs_improvement';
  }

  private _assessProductClarity(asset: any): number {
    // Higher if featured and well-used
    if (asset.isFeatured) return 90;
    if (asset.useCount && asset.useCount > 5) return 80;
    if (asset.useCount && asset.useCount > 0) return 70;
    return 60;
  }

  private _assessBackground(asset: any): 'professional' | 'acceptable' | 'distracting' {
    // Based on usage patterns
    if (asset.isFeatured && asset.useCount > 10) return 'professional';
    if (asset.useCount > 3) return 'acceptable';
    return 'distracting';
  }
}
