import { BadRequestException, Injectable, Logger } from '@nestjs/common';
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
  imageStatus: 'GENERATED' | 'FAILED' | 'PENDING';
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
    const failures: string[] = [];

    const apiKey = await this.resolveOpenAiApiKey();
    this.logger.log(
      `[marketing-image] provider=OPENAI configured=${apiKey ? 'true' : 'false'} category=${input.imageCategory} service=${input.serviceOrProduct}`,
    );
    if (!apiKey) {
      throw new BadRequestException('No hay proveedor de imagenes configurado');
    }

    if (apiKey) {
      try {
        this.logger.log(
          `[marketing-image] generating storyId=n/a mode=edit base=${(input.baseImageUrl || '').trim().length > 0}`,
        );
        const edited = await this.generateWithGptImageEdit(input, prompt, apiKey);
        if (edited) return edited;
      } catch (error) {
        const reason = error instanceof Error ? error.message : String(error);
        this.logger.warn(
          `GPT Image edit failed, trying DALL-E 3 fallback: ${reason}`,
        );
        failures.push(`gpt-image-1-edit: ${reason}`);
      }

      try {
        this.logger.log('[marketing-image] generating storyId=n/a mode=from-scratch');
        const result = await this.generateWithDallE3(input, prompt, apiKey);
        if (result) return result;
      } catch (error) {
        const reason = error instanceof Error ? error.message : String(error);
        this.logger.error(
          `[marketing-image] failed reason=${reason}`,
        );
        failures.push(`dall-e-3: ${reason}`);
      }
    }

    const detail = failures.length > 0 ? failures.join(' | ') : 'sin detalle del proveedor';
    throw new BadRequestException(`No se pudo generar la imagen publicitaria con el proveedor configurado. ${detail}`);
  }

  async isProviderConfigured(): Promise<boolean> {
    const apiKey = await this.resolveOpenAiApiKey();
    return !!apiKey;
  }

  private async generateWithGptImageEdit(
    input: ImageGenerationInput,
    prompt: string,
    apiKey: string,
  ): Promise<ImageGenerationResult | null> {
    const baseImageUrl = (input.baseImageUrl || '').trim();
    if (!baseImageUrl.startsWith('http://') && !baseImageUrl.startsWith('https://')) {
      return null;
    }

    const baseResponse = await fetch(baseImageUrl);
    if (!baseResponse.ok) {
      throw new Error(`Cannot download base image: HTTP ${baseResponse.status}`);
    }

    const baseBuffer = Buffer.from(await baseResponse.arrayBuffer());
    if (baseBuffer.length === 0) {
      throw new Error('Base image downloaded with zero bytes');
    }

    const baseContentType = `${baseResponse.headers.get('content-type') ?? ''}`.toLowerCase().includes('png')
      ? 'image/png'
      : `${baseResponse.headers.get('content-type') ?? ''}`.toLowerCase().includes('webp')
        ? 'image/webp'
        : 'image/jpeg';
    const baseExt = baseContentType === 'image/png' ? 'png' : baseContentType === 'image/webp' ? 'webp' : 'jpg';

    const formData = new FormData();
    formData.append('model', 'gpt-image-1');
    formData.append('prompt', this.buildGptImagePrompt(input));
    formData.append('size', '1024x1792');
    formData.append('quality', 'high');
    formData.append('image', new Blob([baseBuffer], { type: baseContentType }), `base.${baseExt}`);

    const response = await fetch('https://api.openai.com/v1/images/edits', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
      },
      body: formData,
    });

    if (!response.ok) {
      const errorText = await response.text().catch(() => '');
      throw new Error(`GPT Image edit HTTP ${response.status}: ${errorText.slice(0, 300)}`);
    }

    const payload = (await response.json()) as {
      data?: Array<{ b64_json?: string; url?: string }>;
    };

    const edited = payload.data?.[0];
    const b64 = `${edited?.b64_json ?? ''}`.trim();
    const url = `${edited?.url ?? ''}`.trim();
    if (!b64 && !url) {
      throw new Error('GPT Image edit returned no image content');
    }

    let finalUrl = '';
    if (b64) {
      const bytes = Buffer.from(b64, 'base64');
      finalUrl = this.buildDataUrl(bytes, 'image/png');
    } else {
      finalUrl = await this.downloadAsDataUrl(url);
    }

    this.logger.log('[marketing-image] generated bytes/url ok provider=openai/gpt-image-1-edit');

    return {
      imageStatus: 'GENERATED',
      generatedImageUrl: finalUrl,
      generatedImageProvider: 'OPENAI',
      prompt,
      visualConcept: input.visualConcept,
      designNotes: input.designNotes,
      metadata: {
        mode: 'gpt-image-1-edit',
        model: 'gpt-image-1',
        size: '1024x1792',
        quality: 'high',
        baseImageUrl: input.baseImageUrl,
        format: '9:16',
        category: input.imageCategory,
        serviceOrProduct: input.serviceOrProduct,
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

    const dataUrl = await this.downloadAsDataUrl(imageUrl);
    this.logger.log('[marketing-image] generated bytes/url ok provider=openai/dall-e-3');

    return {
      imageStatus: 'GENERATED',
      generatedImageUrl: dataUrl,
      generatedImageProvider: 'OPENAI',
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

  private async downloadAsDataUrl(imageUrl: string): Promise<string> {
    const imageResponse = await fetch(imageUrl);
    if (!imageResponse.ok) {
      throw new Error(`Failed to download generated image: HTTP ${imageResponse.status}`);
    }

    const imageBuffer = Buffer.from(await imageResponse.arrayBuffer());
    const contentType = this.normalizeContentType(`${imageResponse.headers.get('content-type') ?? ''}`);
    return this.buildDataUrl(imageBuffer, contentType);
  }

  private buildDataUrl(imageBuffer: Buffer, contentType: string) {
    return `data:${contentType};base64,${imageBuffer.toString('base64')}`;
  }

  private normalizeContentType(raw: string) {
    const value = `${raw || ''}`.toLowerCase();
    if (value.includes('png')) return 'image/png';
    if (value.includes('webp')) return 'image/webp';
    return 'image/jpeg';
  }

  private buildGptImagePrompt(input: ImageGenerationInput) {
    const colors = input.brandColors.length > 0 ? input.brandColors.join(', ') : 'azul marino, blanco, cian';
    const service = input.serviceOrProduct || input.imageCategory || 'solución de seguridad y tecnología';
    const title = this.truncate(input.title, 72);
    const cta = this.truncate(input.cta, 44);

    return [
      `Edit this base image to create a premium vertical 9:16 social story advertisement for FULLTECH (${input.city}, ${input.country}).`,
      `Keep the original product/service identity recognizable and realistic: ${service}.`,
      'Visual direction: premium commercial campaign, clean background, realistic lighting, soft shadows, modern composition, high depth and contrast.',
      `Brand palette: ${colors}.`,
      `Story objective: ${input.visualConcept}.`,
      `Design notes: ${input.designNotes}.`,
      `Sales angle: ${input.usedResearchAngle}.`,
      'Do not produce cartoon style. Do not overload elements. Keep mobile readability and ad-grade realism.',
      `Suggested headline context: ${title}.`,
      `Suggested CTA context: ${cta}.`,
    ].join(' ');
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
