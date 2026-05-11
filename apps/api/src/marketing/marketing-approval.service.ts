import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { UpdateMarketingStoryDto } from './dto/update-marketing-story.dto';

@Injectable()
export class MarketingApprovalService {
  constructor(private readonly prisma: PrismaService) {}

  async approve(companyId: string, storyId: string, userId: string) {
    const story = await this.prisma.marketingDailyStory.findFirst({
      where: { id: storyId, companyId },
      include: { mediaAsset: true },
    });
    if (!story) throw new NotFoundException('Contenido no encontrado');

    const missing: string[] = [];
    const metadata = ((story as any).imageGenerationMetadata ?? {}) as Record<string, unknown>;
    const hasGeneratedDesign =
      `${(story as any).generatedImageUrl ?? ''}`.trim().length > 0 ||
      `${(story as any).imageUrl ?? ''}`.trim().length > 0;
    if (!hasGeneratedDesign) missing.push('diseño generado');
    const hasCopy =
      `${story.title ?? ''}`.trim().length > 0 &&
      `${story.shortText ?? ''}`.trim().length > 0 &&
      `${(story as any).usedCTA ?? ''}`.trim().length > 0;
    if (!hasCopy) missing.push('copy');
    if (missing.length > 0) {
      throw new ConflictException(`No se puede aprobar: anuncio incompleto (${missing.join(', ')})`);
    }

    const updated = await this.prisma.marketingDailyStory.update({
      where: { id: story.id },
      data: {
        status: 'APPROVED',
        approvedByUserId: userId,
        approvedAt: new Date(),
        rejectedAt: null,
      },
      include: {
        approvedByUser: {
          select: {
            id: true,
            nombreCompleto: true,
          },
        },
      },
    });

    const mediaAssetId = `${(story as any).mediaAssetId ?? ''}`.trim();
    if (mediaAssetId) {
      await this.prisma.marketingMediaAsset.updateMany({
        where: { id: mediaAssetId, companyId },
        data: {
          useCount: { increment: 1 },
          lastUsedAt: new Date(),
        },
      });
    }

    await this.prisma.marketingActivityLog.create({
      data: {
        companyId,
        action: 'MARKETING_STORY_APPROVED',
        description: `Contenido aprobado ${story.id}`,
        userId,
        metadata: {
          storyId: story.id,
          type: story.type,
          mediaAssetId: (story as any).mediaAssetId ?? null,
          usedResearchAngle: (story as any).usedResearchAngle ?? null,
          usedOffer: (story as any).usedOffer ?? null,
        },
      },
    });

    await this.applyLearning(companyId, {
      mediaCategory: (story as any).mediaAsset?.category,
      usedResearchAngle: (story as any).usedResearchAngle,
      usedOffer: (story as any).usedOffer,
      approved: true,
      sourceResearchId: (story as any).researchId ?? null,
    });

    return updated;
  }

  async reject(companyId: string, storyId: string, userId: string, reason?: string) {
    const story = await this.prisma.marketingDailyStory.findFirst({
      where: { id: storyId, companyId },
      include: { mediaAsset: true },
    });
    if (!story) throw new NotFoundException('Contenido no encontrado');

    const updated = await this.prisma.marketingDailyStory.update({
      where: { id: story.id },
      data: {
        status: 'REJECTED',
        approvedByUserId: null,
        approvedAt: null,
        rejectedAt: new Date(),
      },
      include: {
        approvedByUser: {
          select: {
            id: true,
            nombreCompleto: true,
          },
        },
      },
    });

    await this.prisma.marketingActivityLog.create({
      data: {
        companyId,
        action: 'MARKETING_STORY_REJECTED',
        description: `Contenido rechazado ${story.id}`,
        userId,
        metadata: {
          storyId: story.id,
          type: story.type,
          reason: (reason ?? '').trim(),
          mediaAssetId: (story as any).mediaAssetId ?? null,
          usedResearchAngle: (story as any).usedResearchAngle ?? null,
          usedOffer: (story as any).usedOffer ?? null,
        },
      },
    });

    await this.applyLearning(companyId, {
      mediaCategory: (story as any).mediaAsset?.category,
      usedResearchAngle: (story as any).usedResearchAngle,
      usedOffer: (story as any).usedOffer,
      approved: false,
      sourceResearchId: (story as any).researchId ?? null,
      reason: (reason ?? '').trim(),
    });

    return updated;
  }

  private async applyLearning(
    companyId: string,
    input: {
      mediaCategory?: string | null;
      usedResearchAngle?: string | null;
      usedOffer?: string | null;
      approved: boolean;
      sourceResearchId?: string | null;
      reason?: string;
    },
  ) {
    const items: Array<{ category: string; insight: string }> = [];
    if ((input.mediaCategory ?? '').trim()) {
      items.push({
        category: 'IMAGE_CATEGORY',
        insight: `Categoría visual efectiva: ${input.mediaCategory!.trim()}`,
      });
    }
    if ((input.usedResearchAngle ?? '').trim()) {
      items.push({
        category: 'RESEARCH_ANGLE',
        insight: input.usedResearchAngle!.trim(),
      });
    }
    if ((input.usedOffer ?? '').trim()) {
      items.push({
        category: 'OFFER',
        insight: input.usedOffer!.trim(),
      });
    }

    if (items.length === 0) return;

    for (const item of items) {
      const existing = await this.prisma.marketingLearningMemory.findFirst({
        where: {
          companyId,
          category: item.category,
          insight: item.insight,
        },
      });

      const delta = input.approved ? 0.25 : -0.1;
      if (!existing) {
        await this.prisma.marketingLearningMemory.create({
          data: {
            companyId,
            category: item.category,
            insight: item.insight,
            sourceResearchId: input.sourceResearchId ?? null,
            score: Math.max(0.1, 1 + delta),
            status: 'ACTIVE',
            reason: input.approved
              ? 'Aprobado por administrador'
              : `Penalizado por rechazo${input.reason ? `: ${input.reason}` : ''}`,
          },
        });
        continue;
      }

      await this.prisma.marketingLearningMemory.update({
        where: { id: existing.id },
        data: {
          score: Math.max(0.1, existing.score + delta),
          status: 'ACTIVE',
          reason: input.approved
            ? 'Aprobado por administrador'
            : `Penalizado por rechazo${input.reason ? `: ${input.reason}` : ''}`,
        },
      });
    }
  }

  async edit(companyId: string, storyId: string, dto: UpdateMarketingStoryDto, userId: string) {
    const story = await this.prisma.marketingDailyStory.findFirst({
      where: { id: storyId, companyId },
    });
    if (!story) throw new NotFoundException('Contenido no encontrado');

    const updated = await this.prisma.marketingDailyStory.update({
      where: { id: story.id },
      data: {
        ...(dto.title != null ? { title: dto.title.trim() } : {}),
        ...(dto.shortText != null ? { shortText: dto.shortText.trim() } : {}),
        ...(dto.longText != null ? { longText: dto.longText.trim() } : {}),
        ...(dto.hashtags != null
          ? {
              hashtags: dto.hashtags
                .map((item) => item.trim())
                .filter((item) => item.length > 0),
            }
          : {}),
        ...(dto.imagePrompt != null ? { imagePrompt: dto.imagePrompt.trim() } : {}),
        ...(dto.imageUrl != null ? { imageUrl: dto.imageUrl.trim() } : {}),
        ...(dto.mediaAssetId != null ? { mediaAssetId: dto.mediaAssetId.trim() || null } : {}),
        ...(dto.visualConcept != null ? { visualConcept: dto.visualConcept.trim() } : {}),
        ...(dto.designNotes != null ? { designNotes: dto.designNotes.trim() } : {}),
        ...(dto.usedResearchAngle != null ? { usedResearchAngle: dto.usedResearchAngle.trim() } : {}),
        ...(dto.usedOffer != null ? { usedOffer: dto.usedOffer.trim() } : {}),
        ...(dto.usedCTA != null ? { usedCTA: dto.usedCTA.trim() } : {}),
      },
      include: {
        approvedByUser: {
          select: {
            id: true,
            nombreCompleto: true,
          },
        },
      },
    });

    await this.prisma.marketingActivityLog.create({
      data: {
        companyId,
        action: 'MARKETING_STORY_EDITED',
        description: `Contenido editado ${story.id}`,
        userId,
        metadata: {
          storyId: story.id,
          type: story.type,
        },
      },
    });

    return updated;
  }
}
