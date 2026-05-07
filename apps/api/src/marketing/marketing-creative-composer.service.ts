import { Injectable } from '@nestjs/common';
import sharp from 'sharp';
import { MarketingStorageService } from './marketing-storage.service';

type ComposeCreativeInput = {
  storyType: 'SALES' | 'TRUST' | 'EDUCATIONAL';
  title: string;
  shortText: string;
  cta: string;
  offer?: string;
  serviceOrProduct?: string;
  brandColors?: string[];
  backgroundImageUrl?: string | null;
  baseImageUrl?: string | null;
};

type ComposeCreativeResult = {
  dataUrl: string;
  layout: string;
};

type CreativeLayout = {
  name: string;
  hero: { left: number; top: number; width: number; height: number };
  panelLeft: number;
  panelTop: number;
  panelWidth: number;
  panelHeight: number;
  brandLeft: number;
  brandTop: number;
  badgeLeft: number;
  badgeTop: number;
  textLeft: number;
  titleTop: number;
  titleSize: number;
  titleLineHeight: number;
  titleCharsPerLine: number;
  bodyTop: number;
  bodySize: number;
  bodyLineHeight: number;
  bodyCharsPerLine: number;
  ctaLeft: number;
  ctaTop: number;
  ctaWidth: number;
  offerLeft: number;
  offerTop: number;
  offerWidth: number;
};

@Injectable()
export class MarketingCreativeComposerService {
  constructor(private readonly marketingStorage: MarketingStorageService) {}

  async compose(input: ComposeCreativeInput): Promise<ComposeCreativeResult> {
    const width = 1080;
    const height = 1920;
    const colors = this.resolveColors(input.brandColors);
    const layout = this.layoutForType(input.storyType);

    const [backgroundBuffer, baseBuffer] = await Promise.all([
      this.downloadImageBuffer(input.backgroundImageUrl || input.baseImageUrl || ''),
      this.downloadImageBuffer(input.baseImageUrl || ''),
    ]);

    const background = await this.buildBackground({
      width,
      height,
      colors,
      backgroundBuffer: backgroundBuffer || baseBuffer,
    });

    const layers: sharp.OverlayOptions[] = [];
    if (baseBuffer) {
      const hero = await this.buildHeroLayer({
        buffer: baseBuffer,
        width: layout.hero.width,
        height: layout.hero.height,
      });
      layers.push({ input: hero.shadow, left: layout.hero.left - 20, top: layout.hero.top + 32 });
      layers.push({ input: hero.card, left: layout.hero.left, top: layout.hero.top });
      layers.push({ input: hero.image, left: layout.hero.left, top: layout.hero.top });
    }

    const overlay = Buffer.from(
      this.buildOverlaySvg({
        width,
        height,
        colors,
        layout,
        storyType: input.storyType,
        title: this.wrapText(this.clean(input.title), layout.titleCharsPerLine, 3),
        shortText: this.wrapText(this.clean(input.shortText), layout.bodyCharsPerLine, 3),
        cta: this.clean(input.cta) || 'Escribenos por WhatsApp',
        offer: this.wrapText(this.clean(input.offer || input.serviceOrProduct || ''), 26, 2),
      }),
      'utf-8',
    );
    layers.push({ input: overlay, top: 0, left: 0 });

    const output = await sharp(background)
      .composite(layers)
      .jpeg({ quality: 94, chromaSubsampling: '4:4:4' })
      .toBuffer();

    return {
      dataUrl: `data:image/jpeg;base64,${output.toString('base64')}`,
      layout: layout.name,
    };
  }

  private async buildBackground(input: {
    width: number;
    height: number;
    colors: { navy: string; cyan: string; slate: string; soft: string; dark: string };
    backgroundBuffer: Buffer | null;
  }) {
    const base = input.backgroundBuffer
      ? await sharp(input.backgroundBuffer)
          .resize(input.width, input.height, { fit: 'cover', position: 'centre' })
          .blur(24)
          .modulate({ brightness: 0.58, saturation: 1.08 })
          .jpeg({ quality: 92 })
          .toBuffer()
      : await sharp({
          create: {
            width: input.width,
            height: input.height,
            channels: 4,
            background: '#0D1B2A',
          },
        })
          .png()
          .toBuffer();

    const gradient = Buffer.from(
      `<svg width="${input.width}" height="${input.height}" viewBox="0 0 ${input.width} ${input.height}" xmlns="http://www.w3.org/2000/svg">
        <defs>
          <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stop-color="${input.colors.navy}" stop-opacity="0.96"/>
            <stop offset="48%" stop-color="${input.colors.dark}" stop-opacity="0.88"/>
            <stop offset="100%" stop-color="${input.colors.slate}" stop-opacity="0.92"/>
          </linearGradient>
          <radialGradient id="glow" cx="80%" cy="26%" r="52%">
            <stop offset="0%" stop-color="${input.colors.cyan}" stop-opacity="0.35"/>
            <stop offset="100%" stop-color="${input.colors.cyan}" stop-opacity="0"/>
          </radialGradient>
        </defs>
        <rect width="100%" height="100%" fill="url(#bg)"/>
        <rect width="100%" height="100%" fill="url(#glow)"/>
        <rect width="100%" height="100%" fill="rgba(5,10,18,0.20)"/>
      </svg>`,
      'utf-8',
    );

    return sharp(base).composite([{ input: gradient }]).png().toBuffer();
  }

  private async buildHeroLayer(input: { buffer: Buffer; width: number; height: number }) {
    const card = Buffer.from(
      `<svg width="${input.width}" height="${input.height}" viewBox="0 0 ${input.width} ${input.height}" xmlns="http://www.w3.org/2000/svg">
        <defs>
          <linearGradient id="card" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.98"/>
            <stop offset="100%" stop-color="#EAF2F8" stop-opacity="0.92"/>
          </linearGradient>
        </defs>
        <rect x="0" y="0" width="${input.width}" height="${input.height}" rx="42" fill="url(#card)"/>
        <rect x="1.5" y="1.5" width="${input.width - 3}" height="${input.height - 3}" rx="40" fill="none" stroke="rgba(255,255,255,0.65)" stroke-width="3"/>
      </svg>`,
      'utf-8',
    );
    const shadow = Buffer.from(
      `<svg width="${input.width + 40}" height="${input.height + 80}" viewBox="0 0 ${input.width + 40} ${input.height + 80}" xmlns="http://www.w3.org/2000/svg">
        <defs>
          <filter id="blur"><feGaussianBlur stdDeviation="22"/></filter>
        </defs>
        <rect x="20" y="26" width="${input.width}" height="${input.height}" rx="42" fill="rgba(0,0,0,0.42)" filter="url(#blur)"/>
      </svg>`,
      'utf-8',
    );
    const image = await sharp(input.buffer)
      .resize(input.width - 64, input.height - 64, {
        fit: 'contain',
        background: { r: 0, g: 0, b: 0, alpha: 0 },
      })
      .extend({ top: 32, bottom: 32, left: 32, right: 32, background: { r: 0, g: 0, b: 0, alpha: 0 } })
      .png()
      .toBuffer();

    return { shadow, card, image };
  }

  private buildOverlaySvg(input: {
    width: number;
    height: number;
    colors: { navy: string; cyan: string; slate: string; soft: string; dark: string };
    layout: CreativeLayout;
    storyType: 'SALES' | 'TRUST' | 'EDUCATIONAL';
    title: string[];
    shortText: string[];
    cta: string;
    offer: string[];
  }) {
    const badge = input.storyType === 'SALES' ? 'OFERTA PREMIUM' : input.storyType === 'TRUST' ? 'RESPALDO FULLTECH' : 'TIP UTIL';
    const titleLines = input.title
      .map((line, index) => `<tspan x="${input.layout.textLeft}" dy="${index === 0 ? 0 : input.layout.titleLineHeight}">${this.escapeXml(line)}</tspan>`)
      .join('');
    const bodyLines = input.shortText
      .map((line, index) => `<tspan x="${input.layout.textLeft}" dy="${index === 0 ? 0 : input.layout.bodyLineHeight}">${this.escapeXml(line)}</tspan>`)
      .join('');
    const offerLines = input.offer
      .map((line, index) => `<tspan x="${input.layout.offerLeft}" dy="${index === 0 ? 0 : 28}">${this.escapeXml(line)}</tspan>`)
      .join('');

    return `<svg width="${input.width}" height="${input.height}" viewBox="0 0 ${input.width} ${input.height}" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="panel" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" stop-color="rgba(11,22,39,0.88)"/>
          <stop offset="100%" stop-color="rgba(18,34,60,0.74)"/>
        </linearGradient>
      </defs>
      <rect x="${input.layout.panelLeft}" y="${input.layout.panelTop}" width="${input.layout.panelWidth}" height="${input.layout.panelHeight}" rx="34" fill="url(#panel)" stroke="rgba(255,255,255,0.10)" stroke-width="2"/>
      <rect x="${input.layout.brandLeft}" y="${input.layout.brandTop}" width="170" height="42" rx="21" fill="rgba(255,255,255,0.94)"/>
      <text x="${input.layout.brandLeft + 85}" y="${input.layout.brandTop + 28}" text-anchor="middle" font-family="Segoe UI, Arial, sans-serif" font-size="20" font-weight="800" fill="${input.colors.navy}">FULLTECH</text>
      <rect x="${input.layout.badgeLeft}" y="${input.layout.badgeTop}" width="220" height="40" rx="20" fill="${input.colors.cyan}" fill-opacity="0.22" stroke="${input.colors.cyan}" stroke-opacity="0.44"/>
      <text x="${input.layout.badgeLeft + 110}" y="${input.layout.badgeTop + 26}" text-anchor="middle" font-family="Segoe UI, Arial, sans-serif" font-size="17" font-weight="700" fill="#EAFBFF">${this.escapeXml(badge)}</text>
      <text x="${input.layout.textLeft}" y="${input.layout.titleTop}" font-family="Segoe UI, Arial, sans-serif" font-size="${input.layout.titleSize}" font-weight="800" fill="#FFFFFF">${titleLines}</text>
      <text x="${input.layout.textLeft}" y="${input.layout.bodyTop}" font-family="Segoe UI, Arial, sans-serif" font-size="${input.layout.bodySize}" font-weight="500" fill="#DCE8F4">${bodyLines}</text>
      <rect x="${input.layout.ctaLeft}" y="${input.layout.ctaTop}" width="${input.layout.ctaWidth}" height="70" rx="35" fill="#D8FFF0"/>
      <text x="${input.layout.ctaLeft + input.layout.ctaWidth / 2}" y="${input.layout.ctaTop + 44}" text-anchor="middle" font-family="Segoe UI, Arial, sans-serif" font-size="26" font-weight="800" fill="#0E5A40">${this.escapeXml(this.truncate(input.cta, 26))}</text>
      ${input.offer.length > 0 ? `<rect x="${input.layout.offerLeft - 18}" y="${input.layout.offerTop - 28}" width="${input.layout.offerWidth}" height="${input.offer.length > 1 ? 88 : 58}" rx="24" fill="rgba(255,255,255,0.08)"/>
      <text x="${input.layout.offerLeft}" y="${input.layout.offerTop}" font-family="Segoe UI, Arial, sans-serif" font-size="24" font-weight="700" fill="#F3F8FD">${offerLines}</text>` : ''}
    </svg>`;
  }

  private layoutForType(type: 'SALES' | 'TRUST' | 'EDUCATIONAL'): CreativeLayout {
    if (type === 'EDUCATIONAL') {
      return {
        name: 'educational-clean',
        hero: { left: 180, top: 170, width: 720, height: 760 },
        panelLeft: 70,
        panelTop: 1010,
        panelWidth: 940,
        panelHeight: 790,
        brandLeft: 88,
        brandTop: 74,
        badgeLeft: 782,
        badgeTop: 74,
        textLeft: 122,
        titleTop: 1135,
        titleSize: 68,
        titleLineHeight: 76,
        titleCharsPerLine: 18,
        bodyTop: 1380,
        bodySize: 30,
        bodyLineHeight: 40,
        bodyCharsPerLine: 34,
        ctaLeft: 122,
        ctaTop: 1660,
        ctaWidth: 410,
        offerLeft: 122,
        offerTop: 1605,
        offerWidth: 520,
      };
    }
    if (type === 'TRUST') {
      return {
        name: 'trust-editorial',
        hero: { left: 510, top: 270, width: 500, height: 930 },
        panelLeft: 70,
        panelTop: 1180,
        panelWidth: 940,
        panelHeight: 620,
        brandLeft: 88,
        brandTop: 74,
        badgeLeft: 782,
        badgeTop: 74,
        textLeft: 104,
        titleTop: 1295,
        titleSize: 70,
        titleLineHeight: 78,
        titleCharsPerLine: 17,
        bodyTop: 1516,
        bodySize: 30,
        bodyLineHeight: 40,
        bodyCharsPerLine: 34,
        ctaLeft: 104,
        ctaTop: 1680,
        ctaWidth: 390,
        offerLeft: 104,
        offerTop: 1624,
        offerWidth: 520,
      };
    }
    return {
      name: 'sales-hero',
      hero: { left: 470, top: 180, width: 540, height: 980 },
      panelLeft: 70,
      panelTop: 1140,
      panelWidth: 940,
      panelHeight: 660,
      brandLeft: 88,
      brandTop: 74,
      badgeLeft: 782,
      badgeTop: 74,
      textLeft: 104,
      titleTop: 1265,
      titleSize: 74,
      titleLineHeight: 82,
      titleCharsPerLine: 16,
      bodyTop: 1508,
      bodySize: 30,
      bodyLineHeight: 40,
      bodyCharsPerLine: 34,
      ctaLeft: 104,
      ctaTop: 1690,
      ctaWidth: 430,
      offerLeft: 104,
      offerTop: 1628,
      offerWidth: 540,
    };
  }

  private async downloadImageBuffer(rawUrl: string): Promise<Buffer | null> {
    const url = await this.marketingStorage.getPublicUrlAsync(rawUrl || '');
    if (!url || (!url.startsWith('http://') && !url.startsWith('https://') && !url.startsWith('data:image/'))) {
      return null;
    }
    if (url.startsWith('data:image/')) {
      const match = url.match(/^data:image\/[a-zA-Z0-9.+-]+;base64,(.+)$/);
      return match ? Buffer.from(match[1], 'base64') : null;
    }
    try {
      const response = await fetch(url);
      if (!response.ok) return null;
      return Buffer.from(await response.arrayBuffer());
    } catch {
      return null;
    }
  }

  private wrapText(value: string, maxChars: number, maxLines: number) {
    if (!value) return [] as string[];
    const words = value.split(/\s+/).filter(Boolean);
    const lines: string[] = [];
    let current = '';
    for (const word of words) {
      const next = current ? `${current} ${word}` : word;
      if (next.length <= maxChars) {
        current = next;
        continue;
      }
      if (current) lines.push(current);
      current = word;
      if (lines.length === maxLines - 1) break;
    }
    if (lines.length < maxLines && current) lines.push(current);
    if (lines.length > maxLines) return lines.slice(0, maxLines);
    if (words.join(' ').length > lines.join(' ').length && lines.length > 0) {
      lines[lines.length - 1] = this.truncate(lines[lines.length - 1], Math.max(8, maxChars - 3));
    }
    return lines;
  }

  private resolveColors(brandColors?: string[]) {
    const joined = (brandColors || []).join(' ').toLowerCase();
    return {
      navy: joined.includes('#') ? (brandColors?.[0] || '#0D1B2A') : '#0D1B2A',
      cyan: brandColors?.find((item) => item.includes('#')) || '#00B4D8',
      slate: '#16263F',
      soft: '#F3F8FD',
      dark: '#08111F',
    };
  }

  private clean(value: string) {
    return `${value || ''}`.replace(/\s+/g, ' ').trim();
  }

  private truncate(value: string, max: number) {
    const clean = this.clean(value);
    if (clean.length <= max) return clean;
    return `${clean.slice(0, Math.max(0, max - 3)).trim()}...`;
  }

  private escapeXml(value: string) {
    return value
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&apos;');
  }
}