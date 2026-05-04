import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class MarketingLearningService {
  private readonly logger = new Logger(MarketingLearningService.name);

  constructor(private readonly prisma: PrismaService) {}

  async extractAndSave(companyId: string, researchId: string, strongAngles: string[], avoidThis: string[], recommendations: string[]) {
    if (!strongAngles.length && !recommendations.length) return;

    for (const angle of strongAngles) {
      await this.upsertInsight(companyId, researchId, 'strong_angle', angle, 1.0);
    }
    for (const avoid of avoidThis) {
      await this.upsertInsight(companyId, researchId, 'avoid', avoid, 0.8);
    }
    for (const rec of recommendations) {
      await this.upsertInsight(companyId, researchId, 'recommendation', rec, 1.0);
    }
  }

  async boostInsight(companyId: string, insight: string) {
    const existing = await this.prisma.marketingLearningMemory.findFirst({
      where: { companyId, insight, status: 'ACTIVE' },
    });
    if (!existing) return;
    const newScore = Math.min(5.0, existing.score + 0.5);
    await this.prisma.marketingLearningMemory.update({
      where: { id: existing.id },
      data: { score: newScore },
    });
  }

  async penalizeInsight(companyId: string, insight: string) {
    const existing = await this.prisma.marketingLearningMemory.findFirst({
      where: { companyId, insight, status: 'ACTIVE' },
    });
    if (!existing) return;
    const newScore = existing.score - 0.5;
    const status = newScore <= 0 ? 'DISCARDED' : 'ACTIVE';
    await this.prisma.marketingLearningMemory.update({
      where: { id: existing.id },
      data: {
        score: newScore,
        status,
        reason: status === 'DISCARDED' ? 'Score bajó a 0 por rechazos repetidos' : undefined,
      },
    });
  }

  async getActiveInsights(companyId: string, limit = 20) {
    return this.prisma.marketingLearningMemory.findMany({
      where: { companyId, status: 'ACTIVE' },
      orderBy: { score: 'desc' },
      take: limit,
    });
  }

  private async upsertInsight(companyId: string, researchId: string, category: string, insight: string, baseScore: number) {
    const existing = await this.prisma.marketingLearningMemory.findFirst({
      where: { companyId, category, insight },
    });
    if (existing) {
      const newScore = Math.min(5.0, existing.score + 0.2);
      await this.prisma.marketingLearningMemory.update({
        where: { id: existing.id },
        data: { score: newScore, status: 'ACTIVE', updatedAt: new Date() },
      });
    } else {
      await this.prisma.marketingLearningMemory.create({
        data: { companyId, category, insight, sourceResearchId: researchId, score: baseScore, status: 'ACTIVE' },
      });
    }
  }
}
