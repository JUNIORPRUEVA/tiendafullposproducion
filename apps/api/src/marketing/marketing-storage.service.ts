import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join, posix } from 'node:path';
import { R2Service } from '../storage/r2.service';

type SaveImageInput = {
  companyId: string;
  storyType: string;
  sourceUrl: string;
};

@Injectable()
export class MarketingStorageService {
  private readonly logger = new Logger(MarketingStorageService.name);

  constructor(
    private readonly r2: R2Service,
    private readonly config: ConfigService,
  ) {}

  async saveGeneratedImage(input: SaveImageInput) {
    const saved = await this.persistToStorage(input, 'generated');
    return {
      url: saved.url,
      provider: saved.provider,
      metadata: {
        mode: saved.mode,
        storyType: input.storyType,
        companyId: input.companyId,
        objectKey: saved.objectKey,
      },
    };
  }

  async saveBaseImageReference(input: SaveImageInput) {
    const saved = await this.persistToStorage(input, 'base');
    return {
      url: saved.url,
      provider: saved.provider,
      metadata: {
        mode: saved.mode,
        storyType: input.storyType,
        companyId: input.companyId,
        objectKey: saved.objectKey,
      },
    };
  }

  getPublicUrl(objectKeyOrUrl: string) {
    const raw = (objectKeyOrUrl || '').trim();
    if (!raw) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://') || raw.startsWith('data:image/')) {
      return raw;
    }
    if (raw.startsWith('uploads/')) {
      return this.buildPublicUploadsUrl(raw);
    }
    return this.r2.buildPublicUrl(raw);
  }

  getDebugStorageConfig() {
    const uploadDir = this.resolveUploadDir();
    const r2Endpoint = (
      this.config.get<string>('R2_ENDPOINT') ??
      process.env.R2_ENDPOINT ??
      ''
    ).trim();
    const r2Bucket = (
      this.config.get<string>('R2_BUCKET') ??
      process.env.R2_BUCKET ??
      ''
    ).trim();
    const r2AccessKey = (
      this.config.get<string>('R2_ACCESS_KEY_ID') ??
      process.env.R2_ACCESS_KEY_ID ??
      ''
    ).trim();
    const r2Secret = (
      this.config.get<string>('R2_SECRET_ACCESS_KEY') ??
      process.env.R2_SECRET_ACCESS_KEY ??
      ''
    ).trim();
    const hasR2 = !!(r2Endpoint && r2Bucket && r2AccessKey && r2Secret);
    const publicBaseUrl = (
      this.config.get<string>('PUBLIC_BASE_URL') ??
      this.config.get<string>('API_BASE_URL') ??
      process.env.PUBLIC_BASE_URL ??
      process.env.API_BASE_URL ??
      'http://localhost:4000'
    ).trim();

    return {
      storageConfigured: hasR2,
      uploadDir,
      publicBaseUrl,
      r2EndpointConfigured: !!r2Endpoint,
      r2BucketConfigured: !!r2Bucket,
    };
  }

  async getPublicUrlAsync(objectKeyOrUrl: string) {
    const raw = (objectKeyOrUrl || '').trim();
    if (!raw) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://') || raw.startsWith('data:image/')) {
      return raw;
    }
    if (raw.startsWith('uploads/')) {
      return this.buildPublicUploadsUrl(raw);
    }

    const publicUrl = this.r2.buildPublicUrl(raw);
    if (this.isAbsoluteHttpUrl(publicUrl)) {
      return publicUrl;
    }

    try {
      return await this.r2.createPresignedGetUrl({
        objectKey: raw,
        expiresInSeconds: 60 * 60 * 24,
      });
    } catch (error) {
      this.logger.warn(`No se pudo resolver URL pública de imagen legacy: ${error instanceof Error ? error.message : String(error)}`);
      return raw;
    }
  }

  private normalizeUrl(raw: string) {
    const value = (raw || '').trim();
    if (!value) return '';
    return this.getPublicUrl(value);
  }

  private async persistToStorage(input: SaveImageInput, kind: 'base' | 'generated') {
    const normalizedSource = this.normalizeUrl(input.sourceUrl);
    if (!normalizedSource) {
      return {
        url: '',
        provider: 'reference/url',
        mode: `${kind}-empty`,
        objectKey: null as string | null,
      };
    }

    if (normalizedSource.startsWith('data:image/')) {
      const parsed = this.parseDataImage(normalizedSource);
      if (!parsed) {
        return {
          url: normalizedSource,
          provider: 'reference/url',
          mode: `${kind}-data-invalid`,
          objectKey: null as string | null,
        };
      }

      const objectKey = this.buildObjectKey(input, kind, parsed.extension);
      const uploaded = await this.persistBytes(objectKey, parsed.bytes, parsed.contentType);
      if (!uploaded) {
        return {
          url: normalizedSource,
          provider: 'reference/url',
          mode: `${kind}-data-fallback`,
          objectKey: null as string | null,
        };
      }

      return {
        url: uploaded.url,
        provider: 'r2',
        mode: `${kind}-uploaded-data`,
        objectKey,
      };
    }

    if (!this.isAbsoluteHttpUrl(normalizedSource)) {
      return {
        url: normalizedSource,
        provider: 'reference/url',
        mode: `${kind}-relative-reference`,
        objectKey: null as string | null,
      };
    }

    const downloaded = await this.tryDownload(normalizedSource);
    if (!downloaded) {
      return {
        url: normalizedSource,
        provider: 'reference/url',
        mode: `${kind}-download-fallback`,
        objectKey: null as string | null,
      };
    }

    const objectKey = this.buildObjectKey(input, kind, downloaded.extension);
    const uploaded = await this.persistBytes(objectKey, downloaded.bytes, downloaded.contentType);
    if (!uploaded) {
      return {
        url: normalizedSource,
        provider: 'reference/url',
        mode: `${kind}-upload-fallback`,
        objectKey: null as string | null,
      };
    }

    return {
      url: uploaded.url,
      provider: 'r2',
      mode: `${kind}-uploaded`,
      objectKey,
    };
  }

  private async tryDownload(sourceUrl: string) {
    try {
      const response = await fetch(sourceUrl);
      if (!response.ok) {
        this.logger.warn(`No se pudo descargar imagen para marketing (${response.status}): ${sourceUrl}`);
        return null;
      }

      const bytes = Buffer.from(await response.arrayBuffer());
      const rawContentType = `${response.headers.get('content-type') ?? ''}`.trim().toLowerCase();
      const contentType = this.normalizeContentType(rawContentType, sourceUrl);
      const extension = this.extensionFromContentType(contentType);

      if (bytes.length === 0) {
        this.logger.warn(`Descarga vacía de imagen para marketing: ${sourceUrl}`);
        return null;
      }

      return {
        bytes,
        contentType,
        extension,
      };
    } catch (error) {
      this.logger.warn(`Error descargando imagen para marketing: ${error instanceof Error ? error.message : String(error)}`);
      return null;
    }
  }

  private async persistBytes(objectKey: string, body: Buffer, contentType: string) {
    try {
      const absolutePath = this.resolveAbsoluteUploadPath(objectKey);
      await mkdir(join(absolutePath, '..'), { recursive: true }).catch(async () => {
        const parent = absolutePath.split(/[\\/]/).slice(0, -1).join('/');
        if (parent) {
          await mkdir(parent, { recursive: true });
        }
      });
      await writeFile(absolutePath, body);

      await this.r2.putObject({
        objectKey: objectKey.replace(/^uploads\//, ''),
        body,
        contentType,
      });

      this.logger.log(
        `[marketing-image] uploaded objectKey=${objectKey} bytes=${body.length} contentType=${contentType}`,
      );

      return {
        url: this.buildPublicUploadsUrl(objectKey),
      };
    } catch (error) {
      this.logger.warn(`Error subiendo imagen marketing a storage: ${error instanceof Error ? error.message : String(error)}`);
      return null;
    }
  }

  private buildObjectKey(input: SaveImageInput, kind: 'base' | 'generated', extension: string) {
    const date = new Date();
    const yyyy = `${date.getUTCFullYear()}`;
    const mm = `${date.getUTCMonth() + 1}`.padStart(2, '0');
    const safeCompany = this.slugify(input.companyId || 'company');
    const safeType = this.slugify(input.storyType || 'story');
    return `uploads/marketing/${kind}/${yyyy}/${mm}/${safeCompany}-${safeType}-${Date.now()}-${randomUUID()}.${extension}`;
  }

  private parseDataImage(value: string) {
    const match = value.match(/^data:(image\/[a-z0-9.+-]+);base64,(.+)$/i);
    if (!match) return null;

    const contentType = this.normalizeContentType(match[1], '');
    const extension = this.extensionFromContentType(contentType);
    const bytes = Buffer.from(match[2], 'base64');
    if (bytes.length === 0) return null;

    return {
      bytes,
      contentType,
      extension,
    };
  }

  private normalizeContentType(raw: string, sourceUrl: string) {
    if (raw.startsWith('image/')) {
      if (raw.includes('png')) return 'image/png';
      if (raw.includes('webp')) return 'image/webp';
      return 'image/jpeg';
    }

    const lower = sourceUrl.toLowerCase();
    if (lower.includes('.png')) return 'image/png';
    if (lower.includes('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  private extensionFromContentType(contentType: string) {
    if (contentType === 'image/png') return 'png';
    if (contentType === 'image/webp') return 'webp';
    return 'jpg';
  }

  private isAbsoluteHttpUrl(value: string) {
    return value.startsWith('http://') || value.startsWith('https://');
  }

  private resolveUploadDir(): string {
    const fromEnv = (process.env.UPLOAD_DIR ?? '').trim();
    const volumeDir = '/uploads';
    const volumeExists = existsSync(volumeDir);

    if (fromEnv.length > 0) {
      if ((fromEnv === './uploads' || fromEnv === 'uploads') && volumeExists) {
        return volumeDir;
      }
      return fromEnv;
    }

    return volumeExists ? volumeDir : join(process.cwd(), 'uploads');
  }

  private resolveAbsoluteUploadPath(objectKey: string) {
    const uploadDir = this.resolveUploadDir();
    const relativeSegments = objectKey.replace(/^uploads\//, '').split('/');
    return join(uploadDir, ...relativeSegments);
  }

  private buildPublicUploadsUrl(objectKey: string) {
    const base = (
      this.config.get<string>('PUBLIC_BASE_URL') ??
      this.config.get<string>('API_BASE_URL') ??
      process.env.PUBLIC_BASE_URL ??
      process.env.API_BASE_URL ??
      'http://localhost:4000'
    )
      .trim()
      .replace(/\/$/, '');

    const relativePath = `/${posix.join(...objectKey.split(/[/\\]+/))}`;
    return base ? `${base}${relativePath}` : relativePath;
  }

  private slugify(value: string) {
    return `${value || ''}`
      .toLowerCase()
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/-+/g, '-')
      .replace(/^-|-$/g, '')
      .slice(0, 50) || 'item';
  }
}
