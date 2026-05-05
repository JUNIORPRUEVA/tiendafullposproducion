import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import { R2Service } from '../storage/r2.service';

export type PublicidadImageDto = {
  id: string;
  url: string;
  caption?: string;
  uploadedBy: {
    id: string;
    nombreCompleto: string;
  };
  createdAt: string;
};

@Injectable()
export class PublicidadImagesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly r2: R2Service,
    private readonly config: ConfigService,
  ) {}

  async create(data: {
    url: string;
    caption?: string;
    uploadedById: string;
  }): Promise<PublicidadImageDto> {
    const image = await this.prisma.publicidadImage.create({
      data,
      include: {
        uploadedBy: {
          select: { id: true, nombreCompleto: true },
        },
      },
    });

    return {
      id: image.id,
      url: image.url,
      caption: image.caption ?? undefined,
      uploadedBy: image.uploadedBy,
      createdAt: image.createdAt.toISOString(),
    };
  }

  async findAll(): Promise<PublicidadImageDto[]> {
    const images = await this.prisma.publicidadImage.findMany({
      include: {
        uploadedBy: {
          select: { id: true, nombreCompleto: true },
        },
      },
      orderBy: { createdAt: 'desc' },
    });

    return images.map((img) => ({
      id: img.id,
      url: img.url,
      caption: img.caption ?? undefined,
      uploadedBy: img.uploadedBy,
      createdAt: img.createdAt.toISOString(),
    }));
  }

  async delete(id: string): Promise<{ id: string }> {
    await this.prisma.publicidadImage.delete({
      where: { id },
    });
    return { id };
  }

  async update(
    id: string,
    data: { caption?: string },
  ): Promise<PublicidadImageDto> {
    const image = await this.prisma.publicidadImage.update({
      where: { id },
      data,
      include: {
        uploadedBy: {
          select: { id: true, nombreCompleto: true },
        },
      },
    });

    return {
      id: image.id,
      url: image.url,
      caption: image.caption ?? undefined,
      uploadedBy: image.uploadedBy,
      createdAt: image.createdAt.toISOString(),
    };
  }

  async generateUploadUrl(filename: string): Promise<{ uploadUrl: string; objectKey: string; publicUrl: string }> {
    const timestamp = Date.now();
    const objectKey = `publicidad/${timestamp}-${filename}`;
    const contentType = this._inferContentType(filename);

    const uploadUrl = await this.r2.createPresignedPutUrl({
      objectKey,
      contentType,
      expiresInSeconds: 3600,
    });

    const publicUrl = this.r2.buildPublicUrl(objectKey);

    return {
      uploadUrl,
      objectKey,
      publicUrl,
    };
  }

  private _inferContentType(filename: string): string {
    const ext = filename.split('.').pop()?.toLowerCase() ?? '';
    const extMap: Record<string, string> = {
      jpg: 'image/jpeg',
      jpeg: 'image/jpeg',
      png: 'image/png',
      webp: 'image/webp',
      gif: 'image/gif',
      mp4: 'video/mp4',
      webm: 'video/webm',
    };
    return extMap[ext] || 'application/octet-stream';
  }
}
