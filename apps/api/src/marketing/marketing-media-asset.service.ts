import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateMarketingMediaAssetDto, MarketingMediaAssetQueryDto, UpdateMarketingMediaAssetDto } from './dto/marketing-media-asset.dto';

@Injectable()
export class MarketingMediaAssetService {
  constructor(private readonly prisma: PrismaService) {}

  async list(companyId: string, query: MarketingMediaAssetQueryDto) {
    const category = (query.category ?? '').trim();
    const relatedService = (query.related_service ?? '').trim();

    const items = await this.prisma.marketingMediaAsset.findMany({
      where: {
        companyId,
        ...(category ? { category: { equals: category, mode: 'insensitive' } } : {}),
        ...(relatedService ? { relatedService: { equals: relatedService, mode: 'insensitive' } } : {}),
        ...(query.active_only === true ? { isActive: true } : {}),
        ...(query.featured_only === true ? { isFeatured: true } : {}),
      },
      orderBy: [{ isFeatured: 'desc' }, { useCount: 'desc' }, { createdAt: 'desc' }],
      include: {
        stories: {
          select: {
            id: true,
            title: true,
            date: true,
            type: true,
            updatedAt: true,
          },
          orderBy: { updatedAt: 'desc' },
          take: 1,
        },
      },
    });

    return {
      items: items.map((item) => {
        const latestStory = item.stories?.[0] ?? null;
        return {
          ...item,
          tags: Array.isArray(item.tags) ? item.tags : [],
          latestStory,
        };
      }),
    };
  }

  async create(companyId: string, dto: CreateMarketingMediaAssetDto) {
    return this.prisma.marketingMediaAsset.create({
      data: {
        companyId,
        fileUrl: dto.file_url.trim(),
        thumbnailUrl: dto.thumbnail_url?.trim() || null,
        fileName: dto.file_name.trim(),
        mimeType: dto.mime_type.trim(),
        category: dto.category.trim(),
        relatedService: dto.related_service?.trim() || null,
        tags: (dto.tags ?? []).map((item) => item.trim()).filter((item) => item.length > 0),
        description: dto.description?.trim() || null,
        isActive: dto.is_active ?? true,
        isFeatured: dto.is_featured ?? false,
      },
    });
  }

  async update(companyId: string, id: string, dto: UpdateMarketingMediaAssetDto) {
    await this.ensure(companyId, id);
    return this.prisma.marketingMediaAsset.update({
      where: { id },
      data: {
        ...(dto.file_url != null ? { fileUrl: dto.file_url.trim() } : {}),
        ...(dto.thumbnail_url != null ? { thumbnailUrl: dto.thumbnail_url.trim() || null } : {}),
        ...(dto.file_name != null ? { fileName: dto.file_name.trim() } : {}),
        ...(dto.mime_type != null ? { mimeType: dto.mime_type.trim() } : {}),
        ...(dto.category != null ? { category: dto.category.trim() } : {}),
        ...(dto.related_service != null ? { relatedService: dto.related_service.trim() || null } : {}),
        ...(dto.tags != null
          ? {
              tags: dto.tags.map((item) => item.trim()).filter((item) => item.length > 0),
            }
          : {}),
        ...(dto.description != null ? { description: dto.description.trim() || null } : {}),
        ...(dto.is_active != null ? { isActive: dto.is_active } : {}),
        ...(dto.is_featured != null ? { isFeatured: dto.is_featured } : {}),
      },
    });
  }

  async remove(companyId: string, id: string) {
    await this.ensure(companyId, id);

    const references = await this.prisma.marketingDailyStory.count({
      where: { companyId, mediaAssetId: id },
    });
    if (references > 0) {
      throw new ConflictException(
        'No se puede eliminar esta imagen porque ya fue usada en anuncios. Desactívala en lugar de borrarla.',
      );
    }

    await this.prisma.marketingMediaAsset.delete({ where: { id } });
    return { id };
  }

  async touchUsage(companyId: string, id: string) {
    await this.prisma.marketingMediaAsset.updateMany({
      where: { id, companyId },
      data: {
        useCount: { increment: 1 },
        lastUsedAt: new Date(),
      },
    });
  }

  async ensure(companyId: string, id: string) {
    const row = await this.prisma.marketingMediaAsset.findFirst({
      where: { id, companyId },
    });
    if (!row) {
      throw new NotFoundException('Asset de publicidad no encontrado');
    }
    return row;
  }
}
