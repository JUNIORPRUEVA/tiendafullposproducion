import { createHash } from 'crypto';
import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import sharp from 'sharp';
import { PrismaService } from '../prisma/prisma.service';
import { MarketingImageEditProvider } from './marketing-image-edit.provider';

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
  /** Story type for type-specific premium prompts */
  storyType?: 'SALES' | 'TRUST' | 'EDUCATIONAL';
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
    private readonly imageEditProvider: MarketingImageEditProvider,
  ) {}

  async generateOrPrepare(input: ImageGenerationInput): Promise<ImageGenerationResult> {
    const storyType = this.inferStoryType(input);
    const baseImageUrl = (input.baseImageUrl || '').trim();

    if (!baseImageUrl || (!baseImageUrl.startsWith('http://') && !baseImageUrl.startsWith('https://'))) {
      throw new BadRequestException('Selecciona una imagen base válida desde Galería de contenido para generar el diseño final.');
    }

    const mandatoryPrompt =
      'Mantén exactamente el mismo producto de la imagen base. Solo mejora composición publicitaria, iluminación, fondo, profundidad y contexto comercial premium. No reemplazar producto. No agregar texto, logos, marcas de agua ni placeholders. Entrega imagen final lista para publicar en formato vertical 9:16.';

    const prompt = [mandatoryPrompt, this.buildGptImagePrompt(input, storyType)].join(' ');
    this.logger.log(`[marketing-image] provider=image-edit mode=OPENAI storyType=${storyType}`);

    const edited = await this.imageEditProvider.editImage({
      baseImageUrl,
      prompt,
    });

    return {
      imageStatus: 'GENERATED',
      generatedImageUrl: edited.imageDataUrl,
      generatedImageProvider: edited.provider,
      prompt,
      visualConcept: input.visualConcept,
      designNotes: input.designNotes,
      metadata: {
        ...edited.metadata,
        mode: 'image-edit',
        promptType: 'strict-base-image-edit',
      },
    };
  }

  async isProviderConfigured(): Promise<boolean> {
    try {
      await this.imageEditProvider.ensureConfigured();
      return true;
    } catch {
      return false;
    }
  }

  /** Infer story type from explicit field or visual concept/design notes */
  private inferStoryType(input: ImageGenerationInput): 'SALES' | 'TRUST' | 'EDUCATIONAL' {
    if (input.storyType) return input.storyType;
    const vc = (input.visualConcept || '').toLowerCase();
    const dn = (input.designNotes || '').toLowerCase();
    const cat = (input.imageCategory || '').toLowerCase();
    if (
      vc.includes('confianza') || vc.includes('trust') || vc.includes('prueba social') ||
      dn.includes('personas') || dn.includes('equipo') || cat.includes('instalaci')
    ) {
      return 'TRUST';
    }
    if (
      vc.includes('educativ') || vc.includes('educacion') || vc.includes('educational') ||
      dn.includes('infograf') || dn.includes('distribuci') || cat.includes('general')
    ) {
      return 'EDUCATIONAL';
    }
    return 'SALES';
  }

  // â”€â”€ Stability AI Provider â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  private async generateWithStabilityAi(
    input: ImageGenerationInput,
    stabilityKey: string,
    storyType: 'SALES' | 'TRUST' | 'EDUCATIONAL',
  ): Promise<ImageGenerationResult | null> {
    const baseImageUrl = (input.baseImageUrl || '').trim();
    const prompt = this.buildStabilityPrompt(input, storyType);

    let response: Response;
    let mode: string;

    if (baseImageUrl.startsWith('http://') || baseImageUrl.startsWith('https://')) {
      // Image-guided generation: the product image IS the reference â€” preserve its structure
      const imageResponse = await this.fetchWithTimeout(baseImageUrl, undefined, 25000);
      if (!imageResponse.ok) {
        throw new Error(`Cannot download base image for Stability AI: HTTP ${imageResponse.status}`);
      }
      const imageBuffer = Buffer.from(await imageResponse.arrayBuffer());

      const formData = new FormData();
      formData.append('prompt', prompt);
      // 0.75 control strength: strongly preserve product shape and identity
      formData.append('control_strength', '0.75');
      formData.append('aspect_ratio', '9:16');
      formData.append('output_format', 'jpeg');
      formData.append('image', new Blob([imageBuffer], { type: 'image/jpeg' }), 'product.jpg');

      response = await this.fetchWithTimeout('https://api.stability.ai/v2beta/stable-image/control/structure', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${stabilityKey}`,
          Accept: 'application/json',
        },
        body: formData,
      }, 90000);
      mode = 'stability-structure';
    } else {
      // Pure text-to-image
      const formData = new FormData();
      formData.append('prompt', prompt);
      formData.append('aspect_ratio', '9:16');
      formData.append('output_format', 'jpeg');

      response = await this.fetchWithTimeout('https://api.stability.ai/v2beta/stable-image/generate/ultra', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${stabilityKey}`,
          Accept: 'application/json',
        },
        body: formData,
      }, 90000);
      mode = 'stability-ultra';
    }

    if (!response.ok) {
      const errorText = await response.text().catch(() => '');
      throw new Error(`Stability AI HTTP ${response.status}: ${errorText.slice(0, 400)}`);
    }

    const payload = (await response.json()) as { image?: string; finish_reason?: string };
    if (!payload.image) {
      throw new Error(`Stability AI returned no image. finish_reason=${payload.finish_reason ?? 'unknown'}`);
    }

    const bytes = Buffer.from(payload.image, 'base64');
    const dataUrl = this.buildDataUrl(bytes, 'image/jpeg');

    this.logger.log(`[marketing-image] generated provider=STABILITY_AI mode=${mode} type=${storyType}`);

    return {
      imageStatus: 'GENERATED',
      generatedImageUrl: dataUrl,
      generatedImageProvider: 'STABILITY_AI',
      prompt,
      visualConcept: input.visualConcept,
      designNotes: input.designNotes,
      metadata: {
        mode,
        model: mode === 'stability-structure'
          ? 'stable-image/control/structure'
          : 'stable-image/generate/ultra',
        size: '9:16',
        quality: 'ultra',
        baseImageUrl: input.baseImageUrl,
        format: '9:16',
        category: input.imageCategory,
        serviceOrProduct: input.serviceOrProduct,
        storyType,
      },
    };
  }

  private async resolveStabilityApiKey(): Promise<string | null> {
    const envKey = (
      this.config.get<string>('STABILITY_API_KEY') ?? process.env.STABILITY_API_KEY ?? ''
    ).trim();
    return envKey || null;
  }

  /** Premium prompt builder for Stability AI â€” type-specific commercial ad direction */
  private buildStabilityPrompt(
    input: ImageGenerationInput,
    storyType: 'SALES' | 'TRUST' | 'EDUCATIONAL',
  ): string {
    const service = input.serviceOrProduct || input.imageCategory || 'security and automation technology system';
    const city = input.city || 'HigÃ¼ey';
    const country = input.country || 'Dominican Republic';
    const angle = input.usedResearchAngle || 'reliability, professionalism, and real results';
    const offer = input.offer || 'personalized consultation, professional installation included';
    const colors = input.brandColors.length > 0
      ? input.brandColors.join(', ')
      : 'deep navy blue #0D1B2A, clean white, electric cyan #00B4D8';
    const hasProductImage = !!(input.baseImageUrl || '').trim();
    // Core constraint when a real product image is the reference
    const productPreservation = hasProductImage
      ? `CRITICAL PRODUCT RULE: The exact product from the reference image MUST remain the undisputed hero of this image. Preserve the product's exact model, shape, form factor, and visual identity completely â€” it must be 100% recognizable. You may: completely replace/improve the background, add professional lighting, add environmental context (installation scene, office, home), add a technician or person using the product. You MUST NOT: remove the product, replace it with a different product model, substantially distort its shape, or make it unrecognizable. The product is the reason this image exists â€” keep it as the main subject always.`
      : '';

    if (storyType === 'TRUST') {
      return [
        productPreservation,
        `Complete premium vertical 9:16 social media advertisement, STRICT format requirement: 1024x1792 pixels or equivalent 9:16 ratio, fill entire frame top-to-bottom.`,
        hasProductImage
          ? `Subject: The product from the reference image as clear hero, with confident professional service technician (30s, Dominican/Latino appearance, neat professional uniform) actively demonstrating or installing it in modern commercial or upscale residential environment in ${city}, ${country}. Product must be clearly visible and recognizable.`
          : `Subject: Confident professional service technician (30s, Dominican/Latino appearance, neat professional uniform) actively performing installation or service demonstration of ${service} in modern commercial or upscale residential environment.`,
        `People: Real photographic quality human figure, natural authentic expression, professional body language, NOT posed artificially. Clean dark branded work uniform. No deformed hands or faces.`,
        `Environment: Modern organized interior space (commercial office, upscale home, or clean workshop). Contemporary Dominican urban setting. Good quality window light from side.`,
        `Composition: Product and technician as main subjects filling 65% of frame, authentic action moment, product PROMINENTLY VISIBLE and LARGE, upper 15% clean for brand overlay, lower 20% clean for CTA overlay.`,
        `Product prominence: Product MUST be clearly identifiable, large, sharp, and visually dominant. No small product. Product occupies minimum 40% of visible area.`,
        `Lighting: Natural editorial daylight quality, side window key light, clean warm fill, soft professional shadows. Authentic corporate service advertising photography.`,
        `Atmosphere: Premium professional services brand. Trust, reliability, human expertise. Hikvision/Axis partner installation photography quality.`,
        `Quality: Commercial editorial photography at magazine ad quality. Photorealistic only. Zero AI art style. Zero cartoon. Genuine faces only. Every detail sharp and professional.`,
        `Color palette: Natural professional tones, clean whites, deep blues. ${colors}.`,
        `Context: Technology security company in ${city}, ${country}. Sales angle: ${angle}.`,
        `Text encoding: CRITICAL - NO broken text, NO weird characters, NO encoding issues, NO mojibake, NO placeholder text, NO random symbols.`,
        `STRICT: No text IN the image itself. No watermarks. Clean zones for brand and CTA text overlay at top and bottom. Photorealistic humans only. Pure advertisement photography quality.`,
      ].filter(Boolean).join(' ');
    }

    if (storyType === 'EDUCATIONAL') {
      return [
        productPreservation,
        `Complete premium vertical 9:16 educational advertisement photography, STRICT format: 1024x1792 pixels or 9:16 ratio, fill entire frame.`,
        hasProductImage
          ? `Subject: The exact product from reference image as clear visual focus in clean professional studio or modern office environment. Product MUST be LARGE and VISIBLE.`
          : `Subject: ${service} displayed as clear visual focus in clean professional studio or modern office environment. Product MUST be large, visible, and recognizable.`,
        `Background: Clean white, soft warm pearl gray gradient, or light minimalist office surface. Bright, airy, spacious feel.`,
        `Composition: Product CENTERED as PRIMARY SUBJECT, occupying 60-70% of frame height, with generous negative space at top (20%) and bottom (25%) for text overlay. Full product visibility with all features identifiable.`,
        `Product size: Product MUST BE LARGE and PROMINENTLY displayed. Minimum 60% of visible frame area shows product detail.`,
        `Lighting: Bright even studio lighting. Multiple soft box studio lights. Product perfectly illuminated without harsh shadows. Professional product photography standard.`,
        `Product presentation: Ultra sharp detail throughout, professional product isolation, slight 3/4 angle showing depth and features. Every edge crisp and clear.`,
        `Atmosphere: Modern tech brand educational content. Informative, clear, approachable. Apple/Samsung product showcase aesthetic.`,
        `Quality: Ultra-sharp commercial product photography, advertising grade. Every product detail pristine, clear, and professional.`,
        `Color palette: Clean whites, light pearl grays, soft electric blue technology accents. ${colors}.`,
        `Technology context: ${service} for ${city}, ${country} smart technology and security systems.`,
        `Visual concept: ${input.visualConcept || 'Clear professional product showcase for education'}.`,
        `Text encoding: CRITICAL - NO broken text, NO encoding issues, NO placeholder text, NO random symbols, NO weird characters.`,
        `STRICT: No text IN the image. Leave clean zones for overlay. Photorealistic product only. No cluttered background. No animations. Pure photography quality.`,
      ].filter(Boolean).join(' ');
    }

    // SALES (direct sales ad - premium hero product shot)
    return [
      productPreservation,
      `Complete premium vertical 9:16 hero product commercial advertisement, STRICT format requirement: 1024x1792 pixels or 9:16 ratio, fill frame top-to-bottom. SALES advertisement for direct commercial impact.`,
      hasProductImage
        ? `Hero product: The exact product from reference image, elevated to premium commercial advertising quality, displayed as UNDISPUTED STAR of the shot. Product MUST be LARGE, VISIBLE, SHARP, and DOMINANT. Dramatic premium studio environment.`
        : `Hero product: ${service} displayed as UNDISPUTED STAR of the shot. Product MUST be large, visible, recognizable. Dramatic premium studio environment.`,
      `Product prominence: CRITICAL - Product MUST occupy 50-70% of frame height. Product must be absolutely the focal point. No product must be small or secondary. Maximum visual impact on product.`,
      `Background: Deep dark gradient from deep navy blue (#0A1628) at edges to rich charcoal (#1a1a2e) behind product center, subtle atmospheric electric blue-cyan backlight glow emanating from behind product giving depth and premium atmosphere.`,
      `Product presentation: At slight elevated angle (15-20 degrees eye level), ultra-sharp detail across entire product surface, perfect professional isolation, subtle clean shadow beneath product.`,
      `Lighting: Professional cinematic three-point studio: strong warm key light from upper-right creating product highlights, soft blue fill from left, electric blue-cyan rim backlight from behind product creating premium separation glow.`,
      `Surface: Dark premium reflective surface (black granite, dark tempered glass) below product showing clean subtle product reflection.`,
      `Color accents: Electric blue LED ambient glow (#00B4D8), ultra clean white product edge highlights, subtle cyan technology atmosphere. Brand palette: ${colors}.`,
      `Composition: Product HERO centered-to-right occupying 55-70% of frame height. Upper 15% clean dark zone for brand logo. Lower 20% clean zone for price/CTA text. Rule of thirds premium composition.`,
      `Atmosphere: Premium flagship technology product commercial reveal photography. Hikvision/Axis/Samsung product launch quality. Sophisticated, high-value, modern, professional.`,
      `Quality: 8K ultra-realistic commercial product photography. Advertising grade. Pure photographic quality, zero AI art style, zero illustration. Every detail sharp and professional.`,
      `Text encoding: CRITICAL - NO broken text, NO encoding issues, NO placeholder text, NO weird characters, NO mojibake.`,
      `Offer context: ${offer}. Sales angle: ${angle}.`,
      `Technology category: ${service} for ${city}, ${country} security and technology market.`,
      `STRICT: No text IN image. No watermarks. Pure photorealistic product photography. Advertisement ready. Leave clean zones top/bottom for brand/CTA overlay. Published quality.`,
    ].filter(Boolean).join(' ');
  }

  // â”€â”€ OpenAI Providers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  private async generateWithGptImageEdit(
    input: ImageGenerationInput,
    prompt: string,
    apiKey: string,
  ): Promise<ImageGenerationResult | null> {
    const baseImageUrl = (input.baseImageUrl || '').trim();
    if (!baseImageUrl.startsWith('http://') && !baseImageUrl.startsWith('https://')) {
      return null;
    }

    const baseResponse = await this.fetchWithTimeout(baseImageUrl, undefined, 25000);
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
    formData.append('prompt', prompt);
    formData.append('size', '1024x1536'); // portrait 2:3 â€” closest to 9:16 supported by gpt-image-1 edit
    formData.append('quality', 'high');
    formData.append('image', new Blob([baseBuffer], { type: baseContentType }), `base.${baseExt}`);

    const response = await this.fetchWithTimeout('https://api.openai.com/v1/images/edits', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
      },
      body: formData,
    }, 90000);

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
        size: '1024x1536',
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
    storyType: 'SALES' | 'TRUST' | 'EDUCATIONAL' = 'SALES',
  ): Promise<ImageGenerationResult | null> {
    const dallePrompt = this.buildDallE3Prompt(input, storyType);

    const response = await this.fetchWithTimeout('https://api.openai.com/v1/images/generations', {
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
    }, 90000);

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
    const imageResponse = await this.fetchWithTimeout(imageUrl, undefined, 25000);
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

  private async fetchWithTimeout(url: string, init?: RequestInit, timeoutMs = 30000) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      return await fetch(url, {
        ...init,
        signal: controller.signal,
      });
    } catch (error) {
      if ((error as { name?: string })?.name === 'AbortError') {
        throw new Error(`Request timeout after ${timeoutMs}ms`);
      }
      throw error;
    } finally {
      clearTimeout(timer);
    }
  }

  private normalizeContentType(raw: string) {
    const value = `${raw || ''}`.toLowerCase();
    if (value.includes('png')) return 'image/png';
    if (value.includes('webp')) return 'image/webp';
    return 'image/jpeg';
  }

  private buildGptImagePrompt(input: ImageGenerationInput, storyType: 'SALES' | 'TRUST' | 'EDUCATIONAL' = 'SALES') {
    const colors = input.brandColors.length > 0 ? input.brandColors.join(', ') : 'deep navy blue, white, electric cyan';
    const service = input.serviceOrProduct || input.imageCategory || 'security and automation technology';
    const title = this.truncate(input.title, 72);
    const cta = this.truncate(input.cta, 44);

    const typeDirection = storyType === 'TRUST'
      ? `Transform this into a professional editorial advertisement scene showing the technician or professional environment using the product. Add realistic professional lighting, branded uniform context, modern clean workspace environment. Product must remain clearly visible and recognizable.`
      : storyType === 'EDUCATIONAL'
      ? `Transform this into a clean educational product showcase advertisement. Add bright professional studio lighting, clean white/gray minimalist background, ultra-sharp product detail PROMINENTLY VISIBLE. Product MUST be large and occupy 60-70% of frame.`
      : `Transform this into a premium dark-studio hero product advertisement. Add dramatic three-point studio lighting with electric blue-cyan backlight, deep navy gradient background, product surface reflection below, premium cinematic product reveal atmosphere. Product MUST occupy 55-70% of frame and be LARGE, SHARP, VISIBLE.`;

    return [
      `Transform this product image into a premium vertical 9:16 commercial advertisement for FULLTECH SRL in ${input.city}, ${input.country}.`,
      `Product: ${service}.`,
      `CRITICAL: The product in this reference image is the MAIN HERO â€” preserve it completely. Keep the exact product model, shape, and visual identity 100% intact and recognizable. Only change: background, lighting, environment, atmosphere. You may add people, installation context, premium studio setting. DO NOT remove, replace, or significantly alter the product itself.`,
      typeDirection,
      `Product identity preservation: 100% required. The product must be the undisputed focal point of the final image.`,
      `Brand palette: ${colors}.`,
      `Story objective: ${input.visualConcept}.`,
      `Advertising angle: ${input.usedResearchAngle}.`,
      `Leave clean text zones at top 15% and bottom 20% for brand and CTA overlay.`,
      `Quality: 8K commercial photography grade. Photorealistic only. Zero AI art style. Every detail sharp and professional.`,
      `STRICT: No text in image. No watermarks. Pure advertising photography quality. Leave zones clean for overlay.`,
      `Headline context (do not render): ${title}. CTA context (do not render): ${cta}.`,
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

  private buildDallE3Prompt(input: ImageGenerationInput, storyType: 'SALES' | 'TRUST' | 'EDUCATIONAL' = 'SALES'): string {
    const colors = input.brandColors.length > 0 ? input.brandColors.join(', ') : 'deep navy blue #0D1B2A, clean white, electric cyan #00B4D8';
    const service = input.serviceOrProduct || input.imageCategory || 'professional security technology system';

    const typeScene = storyType === 'TRUST'
      ? `Professional service technician (30s, Dominican/Latino, clean dark uniform) actively installing or demonstrating ${service} in modern clean commercial or residential space. Product MUST be clearly visible. Authentic action shot, natural professional expression, editorial corporate photography style.`
      : storyType === 'EDUCATIONAL'
      ? `${service} displayed as LARGE hero product in pristine white studio environment. Product OCCUPIES 60-70% of frame, all features clearly visible, bright professional lighting, clean background. Educational product showcase.`
      : `${service} as dramatic hero product on deep navy-charcoal dark gradient studio background. Product MUST BE LARGE (50-70% of frame). Three-point cinematic lighting: warm key from upper right, soft blue fill from left, cyan rim backlight creating premium separation. Dark surface showing product reflection.`;

    return [
      `Ultra-realistic commercial advertisement photography for FULLTECH SRL in ${input.city}, ${input.country}. STRICT vertical 9:16 portrait format (1024x1792px) for Instagram Stories and WhatsApp Status.`,
      typeScene,
      `Product prominence: Product MUST be LARGE, SHARP, and VISUALLY DOMINANT (minimum 50% of frame). Product must be clearly recognizable.`,
      `Visual concept: ${input.visualConcept}.`,
      `Brand color palette: ${colors}.`,
      `Advertising angle: ${input.usedResearchAngle || 'reliability, professional quality, real results'}.`,
      `Quality requirements: 8K ultra-realistic commercial photography, advertising grade. Zero AI art style, no cartoon, no illustration. Pure photorealistic photography only.`,
      `Text encoding: CRITICAL - NO broken text, NO encoding issues, NO weird characters, NO placeholder text.`,
      `Composition: Leave upper 15% and lower 20% clean zones for brand/CTA text post-production overlays. No text in image itself.`,
      `Design approach: ${input.designNotes}.`,
      `STRICT: No text IN image. No watermarks. No logos in image. Pure photorealistic commercial photography. Advertisement ready for publication.`,
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

  /** Validate generated image: accessibility, image format, dimensions and anti-placeholder checks */
  async validateGeneratedImage(
    imageUrl: string,
    expectedFormat: string = '9:16',
    baseImageUrl?: string,
  ): Promise<{ valid: boolean; reason?: string }> {
    if (!imageUrl?.trim()) {
      return { valid: false, reason: 'Image URL is empty' };
    }

    try {
      const generatedBuffer = await this.loadImageBuffer(imageUrl);
      if (generatedBuffer.length < 12_000) {
        return { valid: false, reason: 'Generated image is too small (likely placeholder or error)' };
      }

      const generatedMeta = await sharp(generatedBuffer).metadata();
      const width = generatedMeta.width ?? 0;
      const height = generatedMeta.height ?? 0;
      if (width < 720 || height < 1200) {
        return { valid: false, reason: `Generated image resolution too low (${width}x${height})` };
      }

      if (expectedFormat === '9:16') {
        const ratio = width / Math.max(1, height);
        const expectedRatio = 9 / 16;
        if (Math.abs(ratio - expectedRatio) > 0.08) {
          return { valid: false, reason: `Generated image has invalid aspect ratio (${width}x${height})` };
        }
      }

      const tinyPreview = await sharp(generatedBuffer)
        .resize(64, 64, { fit: 'cover' })
        .grayscale()
        .raw()
        .toBuffer();
      const generatedHash = createHash('sha256').update(tinyPreview).digest('hex');

      if (baseImageUrl?.trim()) {
        try {
          const baseBuffer = await this.loadImageBuffer(baseImageUrl);
          const basePreview = await sharp(baseBuffer)
            .resize(64, 64, { fit: 'cover' })
            .grayscale()
            .raw()
            .toBuffer();
          const baseHash = createHash('sha256').update(basePreview).digest('hex');
          if (generatedHash === baseHash) {
            return { valid: false, reason: 'Generated image is identical to base image' };
          }
        } catch {
          // If base image cannot be loaded, keep validation based on generated image only.
        }
      }

      const lower = generatedBuffer.subarray(0, Math.min(generatedBuffer.length, 200_000)).toString('latin1').toLowerCase();
      const forbiddenTokens = ['placeholder', 'lorem ipsum', 'dummy image', 'sample image'];
      if (forbiddenTokens.some((token) => lower.includes(token))) {
        return { valid: false, reason: 'Generated image appears to contain placeholder artifacts' };
      }

      return { valid: true };
    } catch (error) {
      const reason = error instanceof Error ? error.message : 'Unknown validation error';
      return { valid: false, reason: `Image validation failed: ${reason}` };
    }
  }

  private async loadImageBuffer(urlOrData: string): Promise<Buffer> {
    if (urlOrData.startsWith('data:')) {
      const parts = urlOrData.split(',');
      if (parts.length < 2 || !parts[1]) {
        throw new Error('Malformed data URL image');
      }
      return Buffer.from(parts[1], 'base64');
    }

    const response = await this.fetchWithTimeout(urlOrData, undefined, 20000);
    if (!response.ok) {
      throw new Error(`Image URL returned HTTP ${response.status}`);
    }

    const contentType = (response.headers.get('content-type') || '').toLowerCase();
    if (!contentType.includes('image')) {
      throw new Error('Response is not an image file');
    }

    return Buffer.from(await response.arrayBuffer());
  }

  buildPrompt(input: ImageGenerationInput) {
    const colors = input.brandColors.length > 0 ? input.brandColors.join(', ') : 'azul oscuro, blanco, turquesa';
    return [
      `Crear diseÃ±o publicitario vertical 9:16 para historia de Instagram/Facebook de ${input.companyName} en ${input.city}, ${input.country}.`,
      `Servicio/producto: ${input.serviceOrProduct || input.imageCategory || 'servicio de seguridad tecnolÃ³gica'}.`,
      `Estilo ${input.brandTone || 'tecnolÃ³gico, limpio y profesional'}.`,
      `Concepto visual: ${input.visualConcept}.`,
      `Ãngulo de venta: ${input.usedResearchAngle || 'confiabilidad y resultados reales'}.`,
      `Oferta recomendada: ${input.offer || 'asesorÃ­a y cotizaciÃ³n personalizada'}.`,
      `Texto principal: "${input.title}".`,
      `CTA: "${input.cta}".`,
      `Colores de marca: ${colors}.`,
      `Notas de diseÃ±o: ${input.designNotes}.`,
      'DiseÃ±o moderno, alta confianza, sin saturar, legible en mÃ³vil.',
    ].join(' ');
  }
}
