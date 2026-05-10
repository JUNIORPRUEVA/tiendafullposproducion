import { BadRequestException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import sharp from 'sharp';

type EditImageInput = {
  baseImageUrl: string;
  prompt: string;
};

type EditImageOutput = {
  imageDataUrl: string;
  provider: 'OPENAI';
  model: string;
  metadata: Record<string, unknown>;
};

@Injectable()
export class MarketingImageEditProvider {
  constructor(private readonly config: ConfigService) {}

  async ensureConfigured() {
    const provider = this.resolveProvider();
    const apiKey = this.resolveOpenAiApiKey();

    if (provider !== 'openai' || !apiKey) {
      throw new BadRequestException(
        'No hay proveedor de edición de imagen configurado. Configura OPENAI_API_KEY o un proveedor compatible con image-to-image.',
      );
    }

    return { provider, apiKey };
  }

  async editImage(input: EditImageInput): Promise<EditImageOutput> {
    const baseImageUrl = (input.baseImageUrl || '').trim();
    if (!baseImageUrl || (!baseImageUrl.startsWith('http://') && !baseImageUrl.startsWith('https://'))) {
      throw new BadRequestException('Selecciona una imagen desde Galería de contenido.');
    }

    const { apiKey } = await this.ensureConfigured();
    const model = (this.config.get<string>('OPENAI_IMAGE_MODEL') ?? process.env.OPENAI_IMAGE_MODEL ?? 'gpt-image-1').trim() || 'gpt-image-1';

    const baseResponse = await this.fetchWithTimeout(baseImageUrl, undefined, 25000);
    if (!baseResponse.ok) {
      throw new BadRequestException(`No se pudo descargar imagen base para edición (HTTP ${baseResponse.status}).`);
    }

    const baseBuffer = Buffer.from(await baseResponse.arrayBuffer());
    if (baseBuffer.length < 2000) {
      throw new BadRequestException('La imagen base es inválida o demasiado pequeña para edición.');
    }

    const baseContentType = this.resolveImageContentType(baseResponse.headers.get('content-type'));
    const extension = baseContentType === 'image/png' ? 'png' : baseContentType === 'image/webp' ? 'webp' : 'jpg';

    const formData = new FormData();
    formData.append('model', model);
    formData.append('prompt', input.prompt);
    formData.append('size', '1024x1536');
    formData.append('quality', 'high');
    formData.append('image', new Blob([baseBuffer], { type: baseContentType }), `base.${extension}`);

    const response = await this.fetchWithTimeout(
      'https://api.openai.com/v1/images/edits',
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
        },
        body: formData,
      },
      90000,
    );

    if (!response.ok) {
      const errorText = await response.text().catch(() => '');
      throw new BadRequestException(`No se pudo editar la imagen con OpenAI (HTTP ${response.status}). ${errorText.slice(0, 240)}`);
    }

    const payload = (await response.json()) as { data?: Array<{ b64_json?: string; url?: string }> };
    const edited = payload.data?.[0];
    const b64 = `${edited?.b64_json ?? ''}`.trim();
    const url = `${edited?.url ?? ''}`.trim();

    if (!b64 && !url) {
      throw new BadRequestException('OpenAI no devolvió imagen editada.');
    }

    const editedBytes = b64
      ? Buffer.from(b64, 'base64')
      : await this.downloadImageBytes(url);

    const normalized = await sharp(editedBytes)
      .resize(1080, 1920, { fit: 'cover', position: 'centre' })
      .jpeg({ quality: 92, chromaSubsampling: '4:4:4' })
      .toBuffer();

    return {
      imageDataUrl: `data:image/jpeg;base64,${normalized.toString('base64')}`,
      provider: 'OPENAI',
      model,
      metadata: {
        mode: 'image-edit',
        model,
        input: 'base-image',
        outputSize: '1080x1920',
      },
    };
  }

  private resolveProvider() {
    return (
      this.config.get<string>('IMAGE_PROVIDER') ??
      process.env.IMAGE_PROVIDER ??
      'openai'
    )
      .trim()
      .toLowerCase();
  }

  private resolveOpenAiApiKey() {
    return (
      this.config.get<string>('OPENAI_API_KEY') ??
      process.env.OPENAI_API_KEY ??
      ''
    ).trim();
  }

  private resolveImageContentType(raw: string | null) {
    const value = `${raw ?? ''}`.toLowerCase();
    if (value.includes('png')) return 'image/png';
    if (value.includes('webp')) return 'image/webp';
    return 'image/jpeg';
  }

  private async downloadImageBytes(url: string) {
    const response = await this.fetchWithTimeout(url, undefined, 25000);
    if (!response.ok) {
      throw new BadRequestException(`No se pudo descargar imagen editada (HTTP ${response.status}).`);
    }
    return Buffer.from(await response.arrayBuffer());
  }

  private async fetchWithTimeout(url: string, init?: RequestInit, timeoutMs: number = 30000) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      return await fetch(url, {
        ...(init ?? {}),
        signal: controller.signal,
      });
    } finally {
      clearTimeout(timer);
    }
  }
}
