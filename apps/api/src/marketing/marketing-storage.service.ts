import { Injectable } from '@nestjs/common';
import { R2Service } from '../storage/r2.service';

type SaveImageInput = {
  companyId: string;
  storyType: string;
  sourceUrl: string;
};

@Injectable()
export class MarketingStorageService {
  constructor(private readonly r2: R2Service) {}

  async saveGeneratedImage(input: SaveImageInput) {
    const url = this.normalizeUrl(input.sourceUrl);
    return {
      url,
      provider: 'reference/url',
      metadata: {
        mode: 'reference',
        storyType: input.storyType,
        companyId: input.companyId,
      },
    };
  }

  async saveBaseImageReference(input: SaveImageInput) {
    const url = this.normalizeUrl(input.sourceUrl);
    return {
      url,
      provider: 'reference/url',
      metadata: {
        mode: 'base-reference',
        storyType: input.storyType,
        companyId: input.companyId,
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
}
