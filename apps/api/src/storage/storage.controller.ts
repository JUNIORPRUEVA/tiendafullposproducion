import {
  BadRequestException,
  Controller,
  Post,
  Req,
  UnauthorizedException,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { randomUUID } from 'node:crypto';
import { extname } from 'node:path';
import { join, posix } from 'node:path';
import * as fs from 'node:fs';
import type { Request } from 'express';
import type { Express } from 'express';
import { FileInterceptor } from '@nestjs/platform-express';
import { memoryStorage } from 'multer';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { sanitizeFileName } from './helpers/storage_helpers';
import { R2Service } from './r2.service';

const allowedMimeTypes = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'video/mp4',
  'video/quicktime',
  'video/webm',
  'video/x-matroska',
]);

const imageExtensions = new Set(['.jpg', '.jpeg', '.png', '.webp']);
const videoExtensions = new Set(['.mp4', '.mov', '.webm', '.mkv']);

function inferContentType(file: Express.Multer.File, safeExt: string): string {
  const mime = (file.mimetype ?? '').trim().toLowerCase();
  if (allowedMimeTypes.has(mime)) return mime;
  if (imageExtensions.has(safeExt)) {
    if (safeExt == '.png') return 'image/png';
    if (safeExt == '.webp') return 'image/webp';
    return 'image/jpeg';
  }
  if (safeExt == '.mov') return 'video/quicktime';
  if (safeExt == '.webm') return 'video/webm';
  if (safeExt == '.mkv') return 'video/x-matroska';
  return 'video/mp4';
}

function inferMediaFolder(contentType: string): 'images' | 'videos' {
  return contentType.startsWith('video/') ? 'videos' : 'images';
}

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('upload')
export class StorageController {
  private readonly publicBaseUrl: string;

  constructor(
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
      if ((fromEnv === './uploads' || fromEnv === 'uploads') && volumeExists) {
        return volumeDir;
      }
      return fromEnv;
    }

    return volumeExists ? volumeDir : join(process.cwd(), 'uploads');
  }

  private buildAbsoluteUrl(req: Request, relativePath: string): string {
    const proto = (req.get('x-forwarded-proto') ?? req.protocol ?? 'http')
      .split(',')[0]
      .trim();
    const host = (req.get('x-forwarded-host') ?? req.get('host') ?? '')
      .split(',')[0]
      .trim();
    const requestBase = host ? `${proto}://${host}` : '';
    const baseUrl = this.publicBaseUrl || requestBase;
    return baseUrl ? `${baseUrl}${relativePath}` : relativePath;
  }

  @Post()
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  @UseInterceptors(
    FileInterceptor('file', {
      storage: memoryStorage(),
      fileFilter: (_req: Express.Request, file: Express.Multer.File, cb: (error: Error | null, acceptFile: boolean) => void) => {
        const mime = (file.mimetype ?? '').trim().toLowerCase();
        const original = (file.originalname ?? '').trim().toLowerCase();
        const ext = extname(original);
        const extAllowed = imageExtensions.has(ext) || videoExtensions.has(ext);
        const mimeAllowed = allowedMimeTypes.has(mime);
        const mimeUnknown = mime.length == 0 || mime == 'application/octet-stream';
        if (mimeAllowed || (mimeUnknown && extAllowed)) {
          return cb(null, true);
        }
        return cb(
          new BadRequestException('Solo se permiten imágenes PNG/JPG/WEBP o videos MP4/MOV/WEBM/MKV'),
          false,
        );
      },
      limits: { fileSize: 60 * 1024 * 1024 },
    }),
  )
  async upload(@Req() req: Request, @UploadedFile() file?: Express.Multer.File) {
    if (!file) {
      throw new BadRequestException('No se subió ningún archivo');
    }

    const auth = req.user as { id?: string } | undefined;
    const userId = (auth?.id ?? '').trim();
    if (!userId) {
      throw new UnauthorizedException('Usuario no autenticado');
    }

    const body = (req.body ?? {}) as Record<string, unknown>;
    const kind = (body['kind'] ?? 'general').toString().trim().toLowerCase() || 'general';
    const original = sanitizeFileName(file.originalname ?? 'archivo');
    const ext = extname(original).toLowerCase();
    const safeExt = imageExtensions.has(ext) || videoExtensions.has(ext)
      ? ext
      : ((file.mimetype ?? '').toLowerCase().startsWith('video/') ? '.mp4' : '.jpg');
    const contentType = inferContentType(file, safeExt);
    const mediaFolder = inferMediaFolder(contentType);
    const fileStem = original.replace(/\.[^/.]+$/, '');
    const now = new Date();
    const yyyy = String(now.getUTCFullYear());
    const mm = String(now.getUTCMonth() + 1).padStart(2, '0');
    const kindFolder = kind.replace(/[^a-z0-9_-]/g, '-');
    const objectKey = [
      'media',
      mediaFolder,
      kindFolder,
      userId,
      yyyy,
      mm,
      `${randomUUID()}-${fileStem}${safeExt}`,
    ]
      .filter((segment) => segment.trim().length > 0)
      .join('/');

    const uploadDir = this.resolveUploadDir();
    const absoluteFilePath = join(uploadDir, ...objectKey.split('/'));
    const absoluteDir = join(uploadDir, 'media', mediaFolder, kindFolder, userId, yyyy, mm);
    fs.mkdirSync(absoluteDir, { recursive: true });
    fs.writeFileSync(absoluteFilePath, file.buffer);

    if (!fs.existsSync(absoluteFilePath)) {
      // eslint-disable-next-line no-console
      console.error(`[upload] file not found after write: ${absoluteFilePath}`);
      throw new BadRequestException('No se pudo persistir el archivo en disco');
    }

    // Optional mirror to R2; local file is source of truth for /uploads serving.
    try {
      await this.r2.putObject({
        objectKey: `uploads/${objectKey}`,
        body: file.buffer,
        contentType,
      });
    } catch (error) {
      // eslint-disable-next-line no-console
      console.warn('[upload] R2 mirror failed, continuing with local storage only', error);
    }

    const relativePath = `/${posix.join('uploads', objectKey)}`;
    const url = this.buildAbsoluteUrl(req, relativePath);
    // eslint-disable-next-line no-console
    console.log(`[upload] saved file=${absoluteFilePath} url=${url}`);

    return {
      url,
      objectKey: `uploads/${objectKey}`,
      relativePath,
      fileName: original,
      kind,
      contentType,
      mediaType: mediaFolder == 'videos' ? 'video' : 'image',
      size: file.size,
    };
  }
}