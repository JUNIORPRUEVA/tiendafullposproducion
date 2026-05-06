import { Injectable, Logger } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { R2Service } from '../storage/r2.service';

type SaveImageInput = {
  companyId: string;
  storyType: string;
  sourceUrl: string;
};

@Injectable()
export class MarketingStorageService {
  private readonly logger = new Logger(MarketingStorageService.name);

  constructor(private readonly r2: R2Service) {}

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
    return this.r2.buildPublicUrl(raw);
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
      const uploaded = await this.tryUpload(objectKey, parsed.bytes, parsed.contentType);
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
    const uploaded = await this.tryUpload(objectKey, downloaded.bytes, downloaded.contentType);
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

  private async tryUpload(objectKey: string, body: Buffer, contentType: string) {
    try {
      await this.r2.putObject({
        objectKey,
        body,
        contentType,
      });

      const publicUrl = this.r2.buildPublicUrl(objectKey);
      const accessibleUrl = this.isAbsoluteHttpUrl(publicUrl)
        ? publicUrl
        : await this.r2.createPresignedGetUrl({
            objectKey,
            expiresInSeconds: 60 * 60 * 24 * 7,
          });

      return {
        url: accessibleUrl,
      };
    } catch (error) {
      this.logger.warn(`Error subiendo imagen marketing a storage: ${error instanceof Error ? error.message : String(error)}`);
      return null;
    }
  }

  private buildObjectKey(input: SaveImageInput, kind: 'base' | 'generated', extension: string) {
    const safeCompany = this.slugify(input.companyId || 'company');
    const safeType = this.slugify(input.storyType || 'story');
    return `marketing/${kind}/${safeCompany}/${safeType}/${Date.now()}-${randomUUID()}.${extension}`;
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
