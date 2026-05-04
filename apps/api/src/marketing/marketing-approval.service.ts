import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { UpdateMarketingStoryDto } from './dto/update-marketing-story.dto';

@Injectable()
export class MarketingApprovalService {
  constructor(private readonly prisma: PrismaService) {}

  async approve(companyId: string, storyId: string, userId: string) {
    const story = await this.prisma.marketingDailyStory.findFirst({
      where: { id: storyId, companyId },
    });
    if (!story) throw new NotFoundException('Contenido no encontrado');

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

    await this.prisma.marketingActivityLog.create({
      data: {
        companyId,
        action: 'MARKETING_STORY_APPROVED',
        description: `Contenido aprobado ${story.id}`,
        userId,
        metadata: { storyId: story.id, type: story.type },
      },
    });

    return updated;
  }

  async reject(companyId: string, storyId: string, userId: string, reason?: string) {
    const story = await this.prisma.marketingDailyStory.findFirst({
      where: { id: storyId, companyId },
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
        },
      },
    });

    return updated;
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
