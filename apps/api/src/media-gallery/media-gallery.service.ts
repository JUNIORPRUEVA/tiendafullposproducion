import { BadRequestException, Injectable } from '@nestjs/common';
import {
  Prisma,
  ServiceEvidenceType,
  ServiceOrderStatus,
  ServiceOrderType,
} from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { SERVICE_ORDER_STATUS_FROM_DB } from '../service-orders/service-orders.constants';
import {
  MediaGalleryInstallationFilter,
  MediaGalleryQueryDto,
  MediaGalleryTypeFilter,
} from './dto/media-gallery-query.dto';

type MediaCursor = {
  createdAt: Date;
  id: string;
};

type MediaGalleryItem = {
  id: string;
  url: string;
  type: 'image' | 'video';
  comment: string;
  orderId: string;
  createdAt: Date;
  uploadedByRole: 'creator' | 'technician';
  orderStatus: 'pendiente' | 'en_proceso' | 'pospuesta' | 'finalizado' | 'cancelado';
  isInstallationCompleted: boolean;
};

@Injectable()
export class MediaGalleryService {
  constructor(private readonly prisma: PrismaService) {}

  async list(query: MediaGalleryQueryDto) {
    const cursor = this.parseCursor(query.cursor);
    const where = this.buildWhere({
      type: query.type,
      installationStatus: query.installationStatus,
      cursor,
    });

    const rows = await this.prisma.serviceEvidence.findMany({
      where,
      take: query.limit + 1,
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      include: {
        serviceOrder: {
          select: {
            id: true,
            status: true,
            serviceType: true,
          },
        },
      },
    });

    const hasMore = rows.length > query.limit;
    const pageRows = hasMore ? rows.slice(0, query.limit) : rows;
    const items = pageRows
      .map((row) => this.mapItem(row))
      .filter((item): item is MediaGalleryItem => item !== null);

    const last = pageRows.length > 0 ? pageRows[pageRows.length - 1] : null;

    return {
      items: items.map((item) => ({
        ...item,
        createdAt: item.createdAt.toISOString(),
      })),
      nextCursor: hasMore && last
        ? this.encodeCursor({ createdAt: last.createdAt, id: last.id })
        : null,
      limit: query.limit,
    };
  }

  private buildWhere({
    type,
    installationStatus,
    cursor,
  }: {
    type: MediaGalleryTypeFilter;
    installationStatus: MediaGalleryInstallationFilter;
    cursor: MediaCursor | null;
  }): Prisma.ServiceEvidenceWhereInput {
    const where: Prisma.ServiceEvidenceWhereInput = {
      type: {
        in: this.resolveEvidenceTypes(type),
      },
    };

    const orderFilter = this.buildOrderFilter(installationStatus);
    if (orderFilter != null) {
      where.serviceOrder = orderFilter;
    }

    if (cursor != null) {
      where.OR = [
        { createdAt: { lt: cursor.createdAt } },
        {
          AND: [{ createdAt: cursor.createdAt }, { id: { lt: cursor.id } }],
        },
      ];
    }

    return where;
  }

  private buildOrderFilter(
    installationStatus: MediaGalleryInstallationFilter,
  ): Prisma.ServiceOrderWhereInput | undefined {
    switch (installationStatus) {
      case 'completed':
        return {
          serviceType: ServiceOrderType.INSTALACION,
          status: ServiceOrderStatus.FINALIZADO,
        };
      case 'pending':
        return {
          NOT: {
            serviceType: ServiceOrderType.INSTALACION,
            status: ServiceOrderStatus.FINALIZADO,
          },
        };
      case 'all':
      default:
        return undefined;
    }
  }

  private resolveEvidenceTypes(
    type: MediaGalleryTypeFilter,
  ): ServiceEvidenceType[] {
    switch (type) {
      case 'image':
        return [
          ServiceEvidenceType.REFERENCIA_IMAGEN,
          ServiceEvidenceType.EVIDENCIA_IMAGEN,
        ];
      case 'video':
        return [
          ServiceEvidenceType.REFERENCIA_VIDEO,
          ServiceEvidenceType.EVIDENCIA_VIDEO,
        ];
      case 'all':
      default:
        return [
          ServiceEvidenceType.REFERENCIA_IMAGEN,
          ServiceEvidenceType.EVIDENCIA_IMAGEN,
          ServiceEvidenceType.REFERENCIA_VIDEO,
          ServiceEvidenceType.EVIDENCIA_VIDEO,
        ];
    }
  }

  private mapItem(
    row: Prisma.ServiceEvidenceGetPayload<{
      include: {
        serviceOrder: {
          select: {
            id: true;
            status: true;
            serviceType: true;
          };
        };
      };
    }>,
  ): MediaGalleryItem | null {
    const url = row.content.trim();
    if (url.length === 0) {
      return null;
    }

    const isReference =
      row.type === ServiceEvidenceType.REFERENCIA_IMAGEN ||
      row.type === ServiceEvidenceType.REFERENCIA_VIDEO;
    const isVideo =
      row.type === ServiceEvidenceType.REFERENCIA_VIDEO ||
      row.type === ServiceEvidenceType.EVIDENCIA_VIDEO;
    const orderStatus = SERVICE_ORDER_STATUS_FROM_DB[row.serviceOrder.status];

    return {
      id: row.id,
      url,
      type: isVideo ? 'video' : 'image',
      comment: '',
      orderId: row.serviceOrderId,
      createdAt: row.createdAt,
      uploadedByRole: isReference ? 'creator' : 'technician',
      orderStatus: orderStatus ?? 'pendiente',
      isInstallationCompleted:
        row.serviceOrder.serviceType === ServiceOrderType.INSTALACION &&
        row.serviceOrder.status === ServiceOrderStatus.FINALIZADO,
    };
  }

  private parseCursor(raw?: string): MediaCursor | null {
    const value = raw?.trim() ?? '';
    if (value.length === 0) return null;

    const separatorIndex = value.indexOf('__');
    if (separatorIndex <= 0 || separatorIndex >= value.length - 2) {
      throw new BadRequestException('Cursor de galería inválido');
    }

    const createdAtRaw = value.substring(0, separatorIndex);
    const id = value.substring(separatorIndex + 2).trim();
    const createdAt = new Date(createdAtRaw);

    if (id.length === 0 || Number.isNaN(createdAt.getTime())) {
      throw new BadRequestException('Cursor de galería inválido');
    }

    return { createdAt, id };
  }

  private encodeCursor(cursor: MediaCursor): string {
    return `${cursor.createdAt.toISOString()}__${cursor.id}`;
  }
}