import { BadRequestException, Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

type EvolutionRuntimeConfig = {
  baseUrl: string;
  instanceName: string;
  apiKey: string;
};

type EvolutionHttpError = {
  status?: number;
  message: string;
  responseBodyPreview?: string;
};

@Injectable()
export class EvolutionWhatsAppService {
  constructor(private readonly prisma: PrismaService) {}

  private cachedConfig: { value: EvolutionRuntimeConfig; atMs: number } | null = null;

  private normalizeBaseUrl(raw: string) {
    const trimmed = raw.trim();
    if (!trimmed) return '';
    return trimmed.endsWith('/') ? trimmed.slice(0, -1) : trimmed;
  }

  normalizeWhatsAppNumber(raw: string) {
    let input = (raw ?? '').toString().trim();
    if (!input) return '';

    const waMeMatch = /wa\.me\/([0-9]+)/i.exec(input);
    if (waMeMatch?.[1]) {
      input = waMeMatch[1];
    }

    input = input.replace(/(@c\.us|@s\.whatsapp\.net)$/i, '');

    let digits = input.replace(/[^0-9]/g, '');
    if (!digits) return '';

    if (digits.startsWith('00')) {
      digits = digits.replace(/^00+/, '');
      if (!digits) return '';
    }

    const isDominicanLocal = digits.length === 10 && /^(809|829|849)/.test(digits);
    if (isDominicanLocal) return `1${digits}`;

    if (digits.length === 11 && digits.startsWith('1')) return digits;

    return digits;
  }

  private async getRuntimeConfig(): Promise<EvolutionRuntimeConfig> {
    const disabled = (process.env.NOTIFICATIONS_ENABLED ?? '').trim().toLowerCase();
    if (disabled === '0' || disabled === 'false') {
      throw new BadRequestException('Notificaciones deshabilitadas por NOTIFICATIONS_ENABLED');
    }

    const now = Date.now();
    if (this.cachedConfig && now - this.cachedConfig.atMs < 30_000) {
      return this.cachedConfig.value;
    }

    const row = await this.prisma.appConfig.findUnique({
      where: { id: 'global' },
      select: {
        evolutionApiBaseUrl: true,
        evolutionApiInstanceName: true,
        evolutionApiApiKey: true,
      },
    });

    const baseUrl = this.normalizeBaseUrl((row?.evolutionApiBaseUrl ?? '').trim());
    const instanceName = (row?.evolutionApiInstanceName ?? '').trim();
    const apiKey = (row?.evolutionApiApiKey ?? '').trim();

    const value = { baseUrl, instanceName, apiKey };
    this.cachedConfig = { value, atMs: now };
    return value;
  }

  private stringifyPreview(value: unknown, maxChars = 900) {
    if (value == null) return '';
    const text = typeof value === 'string' ? value : JSON.stringify(value);
    const trimmed = text.trim();
    if (trimmed.length <= maxChars) return trimmed;
    return `${trimmed.slice(0, maxChars)}…`;
  }

  private async readResponseBodySafe(res: Response) {
    try {
      const text = await res.text();
      return this.stringifyPreview(text);
    } catch {
      return '';
    }
  }

  async sendTextMessage(params: { toNumber: string; message: string }) {
    const mock = (process.env.NOTIFICATIONS_MOCK_SUCCESS ?? '').trim().toLowerCase();
    const mockEnabled = mock === '1' || mock === 'true' || mock === 'yes';

    // Mock mode: validate inputs but skip external calls.
    if (mockEnabled) {
      const number = this.normalizeWhatsAppNumber(params.toNumber);
      if (!number) {
        throw new BadRequestException('Número de WhatsApp inválido');
      }
      const message = (params.message ?? '').toString();
      if (!message.trim()) {
        throw new BadRequestException('Mensaje vacío');
      }
      return;
    }

    const config = await this.getRuntimeConfig();

    if (!config.baseUrl) {
      throw new BadRequestException('Evolution API: falta Base URL en Ajustes > Configuración de API');
    }
    if (!config.instanceName) {
      throw new BadRequestException('Evolution API: falta Instance name en Ajustes > Configuración de API');
    }
    if (!config.apiKey) {
      throw new BadRequestException('Evolution API: falta API Key en Ajustes > Configuración de API');
    }

    const number = this.normalizeWhatsAppNumber(params.toNumber);
    if (!number) {
      throw new BadRequestException('Número de WhatsApp inválido');
    }

    const message = (params.message ?? '').toString();
    if (!message.trim()) {
      throw new BadRequestException('Mensaje vacío');
    }

    const endpoint = `${config.baseUrl}/message/sendText/${encodeURIComponent(config.instanceName)}`;

    const res = await fetch(endpoint, {
      method: 'POST',
      headers: {
        apikey: config.apiKey,
        'content-type': 'application/json',
      },
      body: JSON.stringify({ number, text: message }),
    });

    if (res.ok) return;

    const bodyPreview = await this.readResponseBodySafe(res);
    const err: EvolutionHttpError = {
      status: res.status,
      message: `Evolution API error (HTTP ${res.status})`,
      responseBodyPreview: bodyPreview,
    };

    const error = new Error(
      `${err.message}${err.responseBodyPreview ? ` · Response: ${err.responseBodyPreview}` : ''}`,
    ) as Error & { status?: number };
    (error as any).status = err.status;
    throw error;
  }
}
