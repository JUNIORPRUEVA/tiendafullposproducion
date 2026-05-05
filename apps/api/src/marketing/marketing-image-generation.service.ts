import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import { R2Service } from '../storage/r2.service';

type ImageGenerationInput = {
  companyName: string;
  city: string;
  country: string;
  brandTone: string;
  brandColors: string[];
  title: string;
  cta: string;
  offer: string;
  visualConcept: string;
  designNotes: string;
  baseImageUrl: string;
  imageCategory: string;
  serviceOrProduct: string;
  usedResearchAngle: string;
};

type ImageGenerationResult = {
  imageStatus: 'GENERATED' | 'GENERATED_PLACEHOLDER' | 'PENDING' | 'FAILED';
  generatedImageUrl: string | null;
  generatedImageProvider: string;
  prompt: string;
  visualConcept: string;
  designNotes: string;
  metadata: Record<string, unknown>;
};

@Injectable()
export class MarketingImageGenerationService {
  private readonly logger = new Logger(MarketingImageGenerationService.name);

  constructor(
    private readonly config: ConfigService,
    private readonly prisma: PrismaService,
    private readonly r2: R2Service,
  ) {}

  async generateOrPrepare(input: ImageGenerationInput): Promise<ImageGenerationResult> {
    const prompt = this.buildPrompt(input);

    const apiKey = await this.resolveOpenAiApiKey();
    if (apiKey) {
      try {
        const result = await this.generateWithDallE3(input, prompt, apiKey);
        if (result) return result;
      } catch (error) {
        this.logger.warn(
          `DALL-E 3 generation failed, falling back to placeholder: ${error instanceof Error ? error.message : String(error)}`,
        );
      }
    }

    // Fallback: use the gallery image directly (real product photo, no placeholder text).
    const fallbackUrl = this.buildGalleryImageUrl(input);
    return {
      imageStatus: 'GENERATED_PLACEHOLDER',
      generatedImageUrl: fallbackUrl,
      generatedImageProvider: 'gallery/reference',
      prompt,
      visualConcept: input.visualConcept,
      designNotes: input.designNotes,
      metadata: {
        mode: apiKey ? 'dalle3-failed-gallery-fallback' : 'no-api-key-gallery-fallback',
        baseImageUrl: input.baseImageUrl,
        format: '9:16',
        category: input.imageCategory,
        serviceOrProduct: input.serviceOrProduct,
        headline: this.truncate(input.title, 72),
        cta: this.truncate(input.cta, 44),
      },
    };
  }

  private async generateWithDallE3(
    input: ImageGenerationInput,
    prompt: string,
    apiKey: string,
  ): Promise<ImageGenerationResult | null> {
    const dallePrompt = this.buildDallE3Prompt(input);

    const response = await fetch('https://api.openai.com/v1/images/generations', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'dall-e-3',
        prompt: dallePrompt,
        n: 1,
        size: '1024x1792',
        quality: 'standard',
        style: 'natural',
        response_format: 'url',
      }),
    });

    if (!response.ok) {
      const errorText = await response.text().catch(() => '');
      throw new Error(`DALL-E 3 HTTP ${response.status}: ${errorText.slice(0, 300)}`);
    }

    const payload = (await response.json()) as {
      data?: Array<{ url?: string; revised_prompt?: string }>;
    };

    const imageUrl = payload.data?.[0]?.url;
    const revisedPrompt = payload.data?.[0]?.revised_prompt ?? prompt;

    if (!imageUrl) {
      throw new Error('DALL-E 3 returned no image URL');
    }

    // Download the generated image and upload to R2 for permanent storage.
    const r2Url = await this.downloadAndUploadToR2(imageUrl, input);

    return {
      imageStatus: 'GENERATED',
      generatedImageUrl: r2Url,
      generatedImageProvider: 'openai/dall-e-3',
      prompt: revisedPrompt,
      visualConcept: input.visualConcept,
      designNotes: input.designNotes,
      metadata: {
        mode: 'dall-e-3',
        model: 'dall-e-3',
        size: '1024x1792',
        quality: 'standard',
        style: 'natural',
        baseImageUrl: input.baseImageUrl,
        format: '9:16',
        category: input.imageCategory,
        serviceOrProduct: input.serviceOrProduct,
        headline: this.truncate(input.title, 72),
        cta: this.truncate(input.cta, 44),
      },
    };
  }

  private async downloadAndUploadToR2(imageUrl: string, input: ImageGenerationInput): Promise<string> {
    const imageResponse = await fetch(imageUrl);
    if (!imageResponse.ok) {
      throw new Error(`Failed to download generated image: HTTP ${imageResponse.status}`);
    }

    const imageBuffer = Buffer.from(await imageResponse.arrayBuffer());
    const timestamp = Date.now();
    const slug = this.slugify(input.serviceOrProduct || input.imageCategory || 'publicidad');
    const objectKey = `marketing/generated/${slug}-${timestamp}.jpg`;

    await this.r2.putObject({
      objectKey,
      body: imageBuffer,
      contentType: 'image/jpeg',
    });

    return this.r2.buildPublicUrl(objectKey);
  }

  private async resolveOpenAiApiKey(): Promise<string | null> {
    const envKey = (
      this.config.get<string>('OPENAI_API_KEY') ?? process.env.OPENAI_API_KEY ?? ''
    ).trim();
    if (envKey) return envKey;

    try {
      const appConfig = await this.prisma.appConfig.findUnique({
        where: { id: 'global' },
        select: { openAiApiKey: true },
      });
      const dbKey = (appConfig?.openAiApiKey ?? '').trim();
      if (dbKey) return dbKey;
    } catch {
      // appConfig table may not exist in all environments
    }

    return null;
  }

  private buildDallE3Prompt(input: ImageGenerationInput): string {
    const colors = input.brandColors.length > 0 ? input.brandColors.join(', ') : 'dark blue, white, turquoise';
    const service = input.serviceOrProduct || input.imageCategory || 'security technology service';

    return [
      `Create a vertical 9:16 Instagram/Facebook story advertisement for a technology company called ${input.companyName} based in ${input.city}, ${input.country}.`,
      `The advertisement is for: ${service}.`,
      `Visual style: ${input.brandTone || 'modern, clean, professional technology'}.`,
      `Visual concept: ${input.visualConcept}.`,
      `Brand colors: ${colors}.`,
      `The image must look like a real professional marketing photo of the actual product or service (${service}).`,
      `Show realistic equipment, installations, or technology in use. Do not add text overlays.`,
      `High quality, photorealistic, professional lighting, suitable for social media advertising.`,
      `Sales angle: ${input.usedResearchAngle || 'reliability and real results'}.`,
      `Design notes: ${input.designNotes}.`,
    ].join(' ');
  }

  private buildGalleryImageUrl(input: ImageGenerationInput): string {
    const base = (input.baseImageUrl || '').trim();

    if (base.startsWith('http://') || base.startsWith('https://')) {
      // Return the actual gallery image resized to 9:16 format.
      const normalized = base.replace(/^https?:\/\//, '');
      return `https://images.weserv.nl/?url=${encodeURIComponent(normalized)}&w=1080&h=1920&fit=cover&output=jpg&q=85`;
    }

    return base || '';
  }

  private slugify(value: string): string {
    return (value || '')
      .toLowerCase()
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/-+/g, '-')
      .replace(/^-|-$/g, '')
      .slice(0, 40);
  }

  private truncate(value: string, max: number) {
    const clean = (value || '').replace(/\s+/g, ' ').trim();
    if (clean.length <= max) return clean;
    return `${clean.slice(0, Math.max(0, max - 3)).trim()}...`;
  }

  buildPrompt(input: ImageGenerationInput) {
    const colors = input.brandColors.length > 0 ? input.brandColors.join(', ') : 'azul oscuro, blanco, turquesa';
    return [
      `Crear diseño publicitario vertical 9:16 para historia de Instagram/Facebook de ${input.companyName} en ${input.city}, ${input.country}.`,
      `Servicio/producto: ${input.serviceOrProduct || input.imageCategory || 'servicio de seguridad tecnológica'}.`,
      `Estilo ${input.brandTone || 'tecnológico, limpio y profesional'}.`,
      `Concepto visual: ${input.visualConcept}.`,
      `Ángulo de venta: ${input.usedResearchAngle || 'confiabilidad y resultados reales'}.`,
      `Oferta recomendada: ${input.offer || 'asesoría y cotización personalizada'}.`,
      `Texto principal: "${input.title}".`,
      `CTA: "${input.cta}".`,
      `Colores de marca: ${colors}.`,
      `Notas de diseño: ${input.designNotes}.`,
      'Diseño moderno, alta confianza, sin saturar, legible en móvil.',
    ].join(' ');
  }
}
