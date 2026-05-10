import { BadRequestException, Injectable, Logger } from '@nestjs/common';
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
  private readonly logger = new Logger(MarketingImageEditProvider.name);

  constructor(private readonly config: ConfigService) {}

  async ensureConfigured() {
    const provider = this.resolveProvider();
    const apiKey = this.resolveOpenAiApiKey();

    if (provider !== 'openai' || !apiKey) {
      throw new BadRequestException(
        'No hay proveedor de ediciÃ³n de imagen configurado. Configura OPENAI_API_KEY o un proveedor compatible con image-to-image.',
      );
    }

    return { provider, apiKey };
  }

  async editImage(input: EditImageInput): Promise<EditImageOutput> {
    const baseImageUrl = (input.baseImageUrl || '').trim();
    if (!baseImageUrl || (!baseImageUrl.startsWith('http://') && !baseImageUrl.startsWith('https://'))) {
      throw new BadRequestException('Selecciona una imagen desde GalerÃ­a de contenido.');
    }

    const { apiKey } = await this.ensureConfigured();
    const model = (this.config.get<string>('OPENAI_IMAGE_MODEL') ?? process.env.OPENAI_IMAGE_MODEL ?? 'gpt-image-1').trim() || 'gpt-image-1';

      const size = (this.config.get<string>('OPENAI_IMAGE_SIZE') ?? process.env.OPENAI_IMAGE_SIZE ?? '1024x1536').trim() || '1024x1536';
      const createdAt = new Date().toISOString();

      this.logger.log(`[marketing-image] openai edit request start model=${model} size=${size}`);

      let baseBuffer: Buffer;
      let baseContentType: string;
      try {
        const baseResponse = await this.fetchWithTimeout(baseImageUrl, undefined, 25000);
        if (!baseResponse.ok) {
          throw new BadRequestException(`No se pudo descargar imagen base para ediciÃ³n (HTTP ${baseResponse.status}).`);
        }
        baseBuffer = Buffer.from(await baseResponse.arrayBuffer());
        baseContentType = this.resolveImageContentType(baseResponse.headers.get('content-type'));
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        this.logger.warn(`[marketing-image] openai edit failed base-download: ${msg}`);
        throw err instanceof BadRequestException ? err : new BadRequestException(`No se pudo descargar imagen base: ${msg}`);
      }

      if (baseBuffer.length < 2000) {
        throw new BadRequestException('La imagen base es invÃ¡lida o demasiado pequeÃ±a para ediciÃ³n.');
      }

      this.logger.log(`[marketing-image] baseImageBytes=${baseBuffer.length} baseContentType=${baseContentType}`);
      this.logger.log(`[marketing-image] promptLength=${input.prompt.length}`);

      const extension = baseContentType === 'image/png' ? 'png' : baseContentType === 'image/webp' ? 'webp' : 'jpg';

      const formData = new FormData();
      formData.append('model', model);
      formData.append('prompt', input.prompt);
      formData.append('size', size);
      formData.append('quality', 'high');
      formData.append('image', new Blob([new Uint8Array(baseBuffer)], { type: baseContentType }), `base.${extension}`);

      let responseStatus = 0;
      let responseText = '';
      let payload: unknown;
      try {
        const response = await this.fetchWithTimeout(
          'https://api.openai.com/v1/images/edits',
          {
            method: 'POST',
            headers: { Authorization: `Bearer ${apiKey}` },
            body: formData,
          },
          120000,
        );
        responseStatus = response.status;
        responseText = await response.text().catch(() => '');
        if (!response.ok) {
          this.logger.warn(`[marketing-image] openai edit failed status=${responseStatus} message=${responseText.slice(0, 400)}`);
          throw new BadRequestException(
            `No se pudo editar la imagen con OpenAI (HTTP ${responseStatus}). ${responseText.slice(0, 240)}`,
          );
        }
        try {
          payload = JSON.parse(responseText);
        } catch {
          this.logger.warn(`[marketing-image] openai response not JSON status=${responseStatus} body=${responseText.slice(0, 200)}`);
          throw new BadRequestException(`OpenAI devolviÃ³ respuesta no vÃ¡lida (HTTP ${responseStatus}).`);
        }
      } catch (err) {
        if (err instanceof BadRequestException) throw err;
        const msg = err instanceof Error ? err.message : String(err);
        this.logger.error(`[marketing-image] openai edit network error: ${msg}`);
        throw new BadRequestException(`Error de red al llamar OpenAI image edit: ${msg}`);
      }

      // Support all known OpenAI response shapes:
      // { data: [{ b64_json }] }  |  { data: [{ url }] }  |  { data: { b64_json } }  |  { data: { url } }
      const payloadObj = payload as Record<string, unknown>;
      const dataField = payloadObj['data'];
      const firstItem: Record<string, unknown> = Array.isArray(dataField)
        ? (dataField[0] as Record<string, unknown>) ?? {}
        : (dataField as Record<string, unknown>) ?? {};

      const b64 = `${(firstItem['b64_json'] ?? '') as string}`.trim();
      const imageUrl = `${(firstItem['url'] ?? '') as string}`.trim();

      const responseShape = JSON.stringify({
        topLevelKeys: Object.keys(payloadObj),
        dataType: Array.isArray(dataField) ? 'array' : typeof dataField,
        firstItemKeys: Object.keys(firstItem),
      });

      this.logger.log(`[marketing-image] response keys=${responseShape}`);
      this.logger.log(`[marketing-image] hasB64=${!!b64} hasUrl=${!!imageUrl}`);

      if (!b64 && !imageUrl) {
        this.logger.error(`[marketing-image] openai edit no image in response: ${responseText.slice(0, 400)}`);
        throw new BadRequestException(
          `OpenAI no devolviÃ³ imagen vÃ¡lida. Respuesta: ${responseText.slice(0, 200)}`,
        );
      }

      let editedBytes: Buffer;
      if (b64) {
        editedBytes = Buffer.from(b64, 'base64');
      } else {
        editedBytes = await this.downloadImageBytes(imageUrl);
      }

      this.logger.log(`[marketing-image] outputBytes=${editedBytes.length}`);

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
          size,
          input: 'base-image',
          outputSize: '1080x1920',
          responseShape,
          hasB64: !!b64,
          hasUrl: !!imageUrl,
          createdAt,
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
