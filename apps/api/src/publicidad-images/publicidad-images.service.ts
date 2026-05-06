import { Injectable, BadRequestException, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
import { extname, join } from 'node:path';
import { posix } from 'node:path';
import * as fs from 'node:fs';
import type { Request } from 'express';
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

const imageExtensions = new Set(['.jpg', '.jpeg', '.png', '.webp']);
const maxImageSizeBytes = 15 * 1024 * 1024; // 15 MB

@Injectable()
export class PublicidadImagesService {
  private readonly logger = new Logger(PublicidadImagesService.name);
  private readonly publicBaseUrl: string;

  constructor(
    private readonly prisma: PrismaService,
    private readonly r2: R2Service,
    config: ConfigService,
  ) {
    const base =
      config.get<string>('PUBLIC_BASE_URL') ??
      config.get<string>('API_BASE_URL') ??
      '';
    this.publicBaseUrl = base.trim().replace(/\/$/, '');
  }

  private resolveUploadDir(): string {
    const fromEnv = (process.env.UPLOAD_DIR ?? '').trim();
    const volumeDir = '/uploads';
    const volumeExists = fs.existsSync(volumeDir);
    if (fromEnv.length > 0) {
      if ((fromEnv === './uploads' || fromEnv === 'uploads') && volumeExists) return volumeDir;
      return fromEnv;
    }
    return volumeExists ? volumeDir : join(process.cwd(), 'uploads');
  }

  private buildAbsoluteUrl(req: Request, relativePath: string): string {
    const proto = (req.get('x-forwarded-proto') ?? (req as any).protocol ?? 'http')
      .split(',')[0]
      .trim();
    const host = (req.get('x-forwarded-host') ?? req.get('host') ?? '')
      .split(',')[0]
      .trim();
    const requestBase = host ? `${proto}://${host}` : '';
    const baseUrl = this.publicBaseUrl || requestBase;
    return baseUrl ? `${baseUrl}${relativePath}` : relativePath;
  }

  private _inferContentType(mimetype: string, safeExt: string): string {
    const mime = (mimetype ?? '').toLowerCase();
    if (mime === 'image/png') return 'image/png';
    if (mime === 'image/webp') return 'image/webp';
    if (mime === 'image/gif') return 'image/gif';
    if (mime === 'image/jpeg') return 'image/jpeg';
    if (safeExt === '.png') return 'image/png';
    if (safeExt === '.webp') return 'image/webp';
    if (safeExt === '.gif') return 'image/gif';
    return 'image/jpeg';
  }

  private _toDto(image: {
    id: string;
    url: string;
    caption: string | null;
    uploadedBy: { id: string; nombreCompleto: string };
    createdAt: Date;
  }): PublicidadImageDto {
    return {
      id: image.id,
      url: image.url,
      caption: image.caption ?? undefined,
      uploadedBy: image.uploadedBy,
      createdAt: image.createdAt.toISOString(),
    };
  }

  /** Upload a raw image file, persist it locally (and optionally to R2), then create the DB record. */
  async createFromFile(params: {
    buffer: Buffer;
    originalname: string;
    mimetype: string;
    size: number;
    caption?: string;
    uploadedById: string;
    req: Request;
  }): Promise<PublicidadImageDto> {
    const { buffer, originalname, mimetype, size, caption, uploadedById, req } = params;

    this.logger.log(
      `[upload] start uploadedBy=${uploadedById} original=${originalname} mime=${mimetype} size=${size}`,
    );

    if (size > maxImageSizeBytes) {
      this.logger.warn(
        `[upload] rejected size=${size} reason=max_15mb`,
      );
      throw new BadRequestException('La imagen excede el limite permitido de 15 MB');
    }

    const original = (originalname ?? 'imagen').replace(/[^a-zA-Z0-9._-]/g, '_');
    const rawExt = extname(original).toLowerCase();
    const safeExt = imageExtensions.has(rawExt) ? rawExt : '.jpg';
    const contentType = this._inferContentType(mimetype, safeExt);

    const now = new Date();
    const yyyy = String(now.getUTCFullYear());
    const mm = String(now.getUTCMonth() + 1).padStart(2, '0');
    const objectKey = posix.join('marketing', 'gallery', yyyy, mm, `${randomUUID()}${safeExt}`);

    const uploadDir = this.resolveUploadDir();
    const absoluteDir = join(uploadDir, 'marketing', 'gallery', yyyy, mm);
    const absoluteFilePath = join(uploadDir, ...objectKey.split('/'));
    fs.mkdirSync(absoluteDir, { recursive: true });
    fs.writeFileSync(absoluteFilePath, buffer);
    this.logger.log(
      `[upload] stored file path=${absoluteFilePath}`,
    );

    // Optional R2 mirror — graceful fallback if not configured
    try {
      await this.r2.putObject({ objectKey: `uploads/${objectKey}`, body: buffer, contentType });
      this.logger.log(
        `[upload] mirrored r2 key=uploads/${objectKey}`,
      );
    } catch {
      // R2 not configured or unavailable — local storage is source of truth
      this.logger.warn(
        `[upload] r2 mirror skipped key=uploads/${objectKey}`,
      );
    }

    const relativePath = `/${posix.join('uploads', objectKey)}`;
    const url = this.buildAbsoluteUrl(req, relativePath);

    const image = await this.prisma.publicidadImage.create({
      data: { url, caption: caption?.trim() || null, uploadedById },
      include: { uploadedBy: { select: { id: true, nombreCompleto: true } } },
    });

    this.logger.log(
      `[upload] db saved id=${image.id} url=${image.url}`,
    );

    return this._toDto(image);
  }

  async create(data: { url: string; caption?: string; uploadedById: string }): Promise<PublicidadImageDto> {
    const image = await this.prisma.publicidadImage.create({
      data: { url: data.url, caption: data.caption?.trim() || null, uploadedById: data.uploadedById },
      include: { uploadedBy: { select: { id: true, nombreCompleto: true } } },
    });
    return this._toDto(image);
  }

  async findAll(): Promise<PublicidadImageDto[]> {
    const images = await this.prisma.publicidadImage.findMany({
      include: { uploadedBy: { select: { id: true, nombreCompleto: true } } },
      orderBy: { createdAt: 'desc' },
    });
    return images.map((img) => this._toDto(img));
  }

  async delete(id: string): Promise<{ id: string }> {
    await this.prisma.publicidadImage.delete({ where: { id } });
    return { id };
  }

  async update(id: string, data: { caption?: string }): Promise<PublicidadImageDto> {
    const image = await this.prisma.publicidadImage.update({
      where: { id },
      data: { caption: data.caption?.trim() || null },
      include: { uploadedBy: { select: { id: true, nombreCompleto: true } } },
    });
    return this._toDto(image);
  }
}
