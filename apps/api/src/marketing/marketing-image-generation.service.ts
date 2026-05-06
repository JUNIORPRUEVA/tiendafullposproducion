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
    private readonly r2: R2Service,
  ) {}

  async generateOrPrepare(input: ImageGenerationInput): Promise<ImageGenerationResult> {
    const failures: string[] = [];
    const storyType = this.inferStoryType(input);

    // ── Provider 1: Stability AI (PRIMARY — no billing issues) ─────────────
    const stabilityKey = await this.resolveStabilityApiKey();
    if (stabilityKey) {
      this.logger.log(
        `[marketing-image] trying provider=STABILITY_AI type=${storyType} category=${input.imageCategory} service=${input.serviceOrProduct}`,
      );
      try {
        const result = await this.generateWithStabilityAi(input, stabilityKey, storyType);
        if (result) return result;
      } catch (error) {
        const reason = error instanceof Error ? error.message : String(error);
        this.logger.warn(`Stability AI failed, trying OpenAI: ${reason}`);
        failures.push(`stability-ai: ${reason}`);
      }
    }

    // ── Provider 2: OpenAI (FALLBACK) ───────────────────────────────────────
    const apiKey = await this.resolveOpenAiApiKey();
    this.logger.log(
      `[marketing-image] provider=OPENAI configured=${apiKey ? 'true' : 'false'} category=${input.imageCategory}`,
    );

    if (!apiKey && !stabilityKey) {
      throw new BadRequestException(
        'No hay proveedor de imágenes configurado. Configura STABILITY_API_KEY o OPENAI_API_KEY.',
      );
    }

    if (apiKey) {
      try {
        this.logger.log(
          `[marketing-image] generating mode=gpt-image-edit base=${(input.baseImageUrl || '').trim().length > 0}`,
        );
        const edited = await this.generateWithGptImageEdit(input, this.buildGptImagePrompt(input, storyType), apiKey);
        if (edited) return edited;
      } catch (error) {
        const reason = error instanceof Error ? error.message : String(error);
        this.logger.warn(`GPT Image edit failed, trying DALL-E 3: ${reason}`);
        failures.push(`gpt-image-1-edit: ${reason}`);
      }

      try {
        this.logger.log('[marketing-image] generating mode=dall-e-3');
        const result = await this.generateWithDallE3(input, this.buildPrompt(input), apiKey, storyType);
        if (result) return result;
      } catch (error) {
        const reason = error instanceof Error ? error.message : String(error);
        this.logger.error(`[marketing-image] dall-e-3 failed: ${reason}`);
        failures.push(`dall-e-3: ${reason}`);
      }
    }

    const detail = failures.length > 0 ? failures.join(' | ') : 'sin detalle del proveedor';
    throw new BadRequestException(`No se pudo generar la imagen publicitaria con el proveedor configurado. ${detail}`);
  }

  async isProviderConfigured(): Promise<boolean> {
    const stabilityKey = await this.resolveStabilityApiKey();
    if (stabilityKey) return true;
    const apiKey = await this.resolveOpenAiApiKey();
    return !!apiKey;
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

  // ── Stability AI Provider ──────────────────────────────────────────────────

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
      // Image-guided generation using product image as structure reference
      const imageResponse = await fetch(baseImageUrl);
      if (!imageResponse.ok) {
        throw new Error(`Cannot download base image for Stability AI: HTTP ${imageResponse.status}`);
      }
      const imageBuffer = Buffer.from(await imageResponse.arrayBuffer());

      const formData = new FormData();
      formData.append('prompt', prompt);
      formData.append('control_strength', '0.65');
      formData.append('aspect_ratio', '9:16');
      formData.append('output_format', 'jpeg');
      formData.append('image', new Blob([imageBuffer], { type: 'image/jpeg' }), 'product.jpg');

      response = await fetch('https://api.stability.ai/v2beta/stable-image/control/structure', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${stabilityKey}`,
          Accept: 'application/json',
        },
        body: formData,
      });
      mode = 'stability-structure';
    } else {
      // Pure text-to-image
      const formData = new FormData();
      formData.append('prompt', prompt);
      formData.append('aspect_ratio', '9:16');
      formData.append('output_format', 'jpeg');

      response = await fetch('https://api.stability.ai/v2beta/stable-image/generate/ultra', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${stabilityKey}`,
          Accept: 'application/json',
        },
        body: formData,
      });
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

  /** Premium prompt builder for Stability AI — type-specific commercial ad direction */
  private buildStabilityPrompt(
    input: ImageGenerationInput,
    storyType: 'SALES' | 'TRUST' | 'EDUCATIONAL',
  ): string {
    const service = input.serviceOrProduct || input.imageCategory || 'security and automation technology system';
    const city = input.city || 'Higüey';
    const country = input.country || 'Dominican Republic';
    const angle = input.usedResearchAngle || 'reliability, professionalism, and real results';
    const offer = input.offer || 'personalized consultation, professional installation included';
    const colors = input.brandColors.length > 0
      ? input.brandColors.join(', ')
      : 'deep navy blue #0D1B2A, clean white, electric cyan #00B4D8';

    if (storyType === 'TRUST') {
      return [
        `Ultra-realistic professional editorial advertisement photography, strict vertical 9:16 portrait format.`,
        `Subject: A confident professional service technician (30s, Dominican/Latino appearance, neat professional uniform) actively performing installation or service demonstration of ${service} in a modern commercial or upscale residential environment.`,
        `People: Real photographic quality human figure, natural authentic expression, professional body language, NOT posed artificially. Clean dark branded work uniform.`,
        `Environment: Modern organized interior space (commercial office, upscale home, or clean workshop). Contemporary Dominican urban setting. Good quality window light entering from side.`,
        `Composition: Technician and product as main subjects filling 65% of frame, authentic action moment captured, upper zone clean for brand placement, product visibly identified.`,
        `Lighting: Natural editorial daylight quality, side window key light, clean warm fill, soft professional shadows. Authentic corporate service advertising photography.`,
        `Atmosphere: Premium professional services brand. Trust, reliability, human expertise. Similar to Hikvision/Axis partner installation imagery.`,
        `Quality: Commercial editorial photography at magazine ad quality. Photorealistic. Zero AI cartoon style. Genuine human faces only.`,
        `Color palette: Natural professional tones, clean whites, deep blues. ${colors}.`,
        `Context: Technology security company in ${city}, ${country}. Sales angle: ${angle}.`,
        `STRICT: No text in image. No watermarks. Photorealistic humans only. No deformed faces or hands. Natural professional scene.`,
      ].join(' ');
    }

    if (storyType === 'EDUCATIONAL') {
      return [
        `Ultra-realistic professional educational advertisement photography, strict vertical 9:16 portrait format.`,
        `Subject: ${service} displayed as the clear visual focus in a clean professional studio or modern office environment.`,
        `Background: Clean white, soft warm pearl gray gradient, or modern light minimalist office surface. Bright, airy, spacious feel.`,
        `Composition: Product centered as primary subject with generous negative space at top (20%) and bottom (25%) for text overlay. Clean product photography perspective. Full product visibility with all features identifiable.`,
        `Lighting: Bright even studio lighting. Three soft box studio lights. Product perfectly illuminated without harsh shadows. Professional product photography standard.`,
        `Product presentation: Ultra sharp detail throughout, professional isolation, slight 3/4 angle view showing product depth and all key features.`,
        `Atmosphere: Modern tech brand educational content. Informative, clear, approachable. Apple/Samsung how-to content aesthetic.`,
        `Quality: Ultra-sharp commercial product photography, advertising grade. Every product detail pristine and clear.`,
        `Color palette: Clean whites, light pearl grays, soft electric blue technology accents. ${colors}.`,
        `Technology context: ${service} for ${city}, ${country} smart technology and security systems.`,
        `Visual concept: ${input.visualConcept || 'Clear educational product showcase'}.`,
        `STRICT: No text in image. Photorealistic product only. No people. No cluttered background.`,
      ].join(' ');
    }

    // SALES (direct sales ad - the premium hero product shot)
    return [
      `Ultra-realistic premium hero product advertisement photography, strict vertical 9:16 portrait format. Direct sales commercial ad.`,
      `Hero product: ${service} displayed as the undisputed star of the shot in a dramatic premium studio environment.`,
      `Background: Deep dark gradient from deep navy blue (#0A1628) at edges transitioning to rich charcoal (#1a1a2e) behind product center, with subtle atmospheric electric blue-cyan backlight glow emanating from behind the product giving depth and premium atmosphere.`,
      `Product presentation: ${service} at slight elevated angle (15-20 degrees from eye level), ultra-sharp detail across entire product surface, perfect professional product isolation, subtle clean shadow directly beneath product.`,
      `Lighting: Professional cinematic three-point studio setup: strong warm key light from upper-right creating product depth highlights, soft blue fill from left preventing pure shadow, electric blue-cyan rim backlight from behind product creating premium separation glow from background.`,
      `Surface: Dark premium reflective surface (like black granite or dark tempered glass) below product showing clean subtle product reflection.`,
      `Color accents: Electric blue LED ambient glow (#00B4D8), ultra clean white product edge highlights, subtle cyan technology atmosphere. Brand palette: ${colors}.`,
      `Composition: Product hero centered-to-right occupying 55-60% of frame height. Upper 15% intentionally clean dark zone reserved for brand logo. Lower 20% semi-clean gradient zone reserved for price and CTA text. Rule of thirds premium composition.`,
      `Atmosphere: Premium flagship technology product commercial reveal photography. Hikvision/Axis/Samsung product launch commercial quality. Sophisticated, high-value, modern.`,
      `Quality: 8K ultra-realistic commercial product photography. Advertising grade. Photographic quality only, zero AI art style, zero illustration.`,
      `Offer context: ${offer}. Sales angle: ${angle}.`,
      `Technology category: ${service} for ${city}, ${country} security and technology market.`,
      `STRICT: No text in image. No watermarks. Pure photorealistic product photography. Advertising ready. Leave clean text zones.`,
    ].join(' ');
  }

  // ── OpenAI Providers ───────────────────────────────────────────────────────

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
    formData.append('prompt', prompt);
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
    storyType: 'SALES' | 'TRUST' | 'EDUCATIONAL' = 'SALES',
  ): Promise<ImageGenerationResult | null> {
    const dallePrompt = this.buildDallE3Prompt(input, storyType);

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

  private buildGptImagePrompt(input: ImageGenerationInput, storyType: 'SALES' | 'TRUST' | 'EDUCATIONAL' = 'SALES') {
    const colors = input.brandColors.length > 0 ? input.brandColors.join(', ') : 'deep navy blue, white, electric cyan';
    const service = input.serviceOrProduct || input.imageCategory || 'security and automation technology';
    const title = this.truncate(input.title, 72);
    const cta = this.truncate(input.cta, 44);

    const typeDirection = storyType === 'TRUST'
      ? `Transform this into a professional editorial advertisement scene showing the technician or professional environment. Add realistic professional lighting, branded uniform context, modern clean workspace environment.`
      : storyType === 'EDUCATIONAL'
      ? `Transform this into a clean educational product showcase advertisement. Add bright professional studio lighting, clean white/gray minimalist background, ultra-sharp product detail visible.`
      : `Transform this into a premium dark-studio hero product advertisement. Add dramatic three-point studio lighting with electric blue-cyan backlight, deep navy gradient background, product surface reflection below, premium cinematic product reveal atmosphere.`;

    return [
      `Transform this product image into a premium vertical 9:16 commercial advertisement for FULLTECH SRL in ${input.city}, ${input.country}.`,
      `Product: ${service}.`,
      typeDirection,
      `Keep product identity 100% recognizable and elevate to commercial advertising photography quality.`,
      `Brand palette: ${colors}.`,
      `Story objective: ${input.visualConcept}.`,
      `Advertising angle: ${input.usedResearchAngle}.`,
      `Leave clean text zones at top 15% and bottom 20% of frame for brand and CTA overlay.`,
      `Quality: 8K commercial photography grade. Photorealistic only. Zero AI art style.`,
      `STRICT: No text in image. No watermarks. Pure advertising photography quality.`,
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
      ? `Professional service technician (30s, Dominican/Latino, clean dark uniform) actively installing or demonstrating ${service} in a modern clean commercial or residential space. Authentic action shot, natural professional expression, editorial corporate photography style.`
      : storyType === 'EDUCATIONAL'
      ? `${service} displayed as hero product in pristine white studio environment. Perfect product photography with all features clearly visible, bright even professional lighting, clean minimal background. Educational product showcase composition.`
      : `${service} as dramatic hero product on deep navy-charcoal dark gradient studio background. Three-point cinematic lighting: warm key light from upper right, soft blue fill from left, electric cyan-blue rim backlight creating premium product separation glow. Dark reflective surface below showing subtle product reflection. Sophisticated premium tech brand commercial reveal.`;

    return [
      `Ultra-realistic commercial advertisement photography for FULLTECH SRL technology company in ${input.city}, ${input.country}. Vertical 9:16 portrait format optimized for Instagram Stories and WhatsApp Status.`,
      typeScene,
      `Visual concept: ${input.visualConcept}.`,
      `Brand color palette: ${colors}.`,
      `Advertising angle: ${input.usedResearchAngle || 'reliability, professional quality, and real results'}.`,
      `Quality requirements: 8K ultra-realistic commercial photography, advertising grade, zero AI art style, no cartoon, no illustration, pure photorealistic.`,
      `Composition: Leave upper 15% and lower 20% as intentionally clean zones for brand/CTA text post-production overlays.`,
      `Design approach: ${input.designNotes}.`,
      `STRICT: No text in image. No watermarks. No logos in image. Pure photorealistic commercial photography only. Advertising ready.`,
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
