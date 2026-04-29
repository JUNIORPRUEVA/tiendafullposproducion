import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import * as http from 'node:http';
import * as https from 'node:https';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import { CreateWhatsappInstanceDto } from './dto/create-whatsapp-instance.dto';

@Injectable()
export class WhatsappService {
  private readonly requestTimeoutMs = 10_000;

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {
    // Startup sanity-check: Evolution API URL must NOT point to this server itself.
    const evoUrl = (config.get<string>('EVOLUTION_API_URL') ?? '').trim().replace(/\/$/, '');
    const selfUrl = (config.get<string>('PUBLIC_BASE_URL') ?? '').trim().replace(/\/$/, '');
    if (!evoUrl) {
      console.warn(
        '[WhatsApp] ADVERTENCIA: EVOLUTION_API_URL no está configurada. Las funciones de WhatsApp no funcionarán.',
      );
    } else if (!/^https?:\/\//i.test(evoUrl)) {
      console.error(
        `[WhatsApp] CONFIGURACION INVALIDA: EVOLUTION_API_URL debe iniciar con http:// o https://. Valor actual: ${evoUrl}`,
      );
    } else if (
      selfUrl &&
      evoUrl.toLowerCase() === selfUrl.toLowerCase()
    ) {
      console.error(
        `[WhatsApp] ¡CONFIGURACIÓN CRÍTICA INCORRECTA! EVOLUTION_API_URL apunta a este mismo servidor (${evoUrl}). ` +
          'Debes configurar EVOLUTION_API_URL con la URL del servidor Evolution API externo, NO la de este API.',
      );
    }
  }

  private get evolutionBaseUrl(): string {
    const raw = (this.config.get<string>('EVOLUTION_API_URL') ?? '').trim();
    if (!raw) return '';
    if (!/^https?:\/\//i.test(raw)) {
      throw new ServiceUnavailableException(
        `EVOLUTION_API_URL invalida: debe iniciar con http:// o https://. Valor actual: ${raw}`,
      );
    }
    return raw.endsWith('/') ? raw.slice(0, -1) : raw;
  }

  private get evolutionApiKey(): string {
    return (this.config.get<string>('EVOLUTION_API_KEY') ?? '').trim();
  }

  private buildHeaders() {
    return {
      'Content-Type': 'application/json',
      apikey: this.evolutionApiKey,
    };
  }

  private resolvePublicBaseUrl(): string {
    const raw = (
      this.config.get<string>('PUBLIC_BASE_URL') ??
      this.config.get<string>('API_BASE_URL') ??
      ''
    ).trim();
    if (!raw) {
      throw new ServiceUnavailableException(
        'PUBLIC_BASE_URL o API_BASE_URL no está configurada para construir el webhook de WhatsApp.',
      );
    }
    if (!/^https?:\/\//i.test(raw)) {
      throw new ServiceUnavailableException(
        `PUBLIC_BASE_URL inválida: debe iniciar con http:// o https://. Valor actual: ${raw}`,
      );
    }
    return raw.endsWith('/') ? raw.slice(0, -1) : raw;
  }

  private buildWebhookUrl(instanceName: string): string {
    return `${this.resolvePublicBaseUrl()}/whatsapp-inbox/webhook/${encodeURIComponent(instanceName)}`;
  }

  private async isGlobalWebhookEnabled(): Promise<boolean> {
    try {
      const config = await this.prisma.appConfig.upsert({
        where: { id: 'global' },
        create: { id: 'global' },
        update: {},
      });
      return !!config.whatsappWebhookEnabled;
    } catch (error) {
      console.warn(
        `[WhatsApp][Webhook] No se pudo leer app_config para webhook global: ${this.describeEvolutionError(error)}`,
      );
      return false;
    }
  }

  private async configureInstanceWebhook(
    instanceName: string,
    enabled: boolean,
  ): Promise<void> {
    try {
      const payload = {
        enabled,
        url: this.buildWebhookUrl(instanceName),
        webhook_by_events: false,
        webhook_base64: false,
        events: ['MESSAGES_UPSERT'],
      };

      await this.fetchEvolution(`/webhook/set/${encodeURIComponent(instanceName)}`, {
        method: 'POST',
        body: JSON.stringify(payload),
      });

      console.log(
        `[WhatsApp][Webhook] Configurado webhook para "${instanceName}" enabled=${enabled}`,
      );
    } catch (error) {
      console.error(
        `[WhatsApp][Webhook] No se pudo configurar webhook para "${instanceName}" enabled=${enabled}: ${this.describeEvolutionError(error)}`,
      );
    }
  }

  async syncWebhookConfigurationForAllInstances(enabled: boolean) {
    const instances = await this.prisma.userWhatsappInstance.findMany({
      select: { instanceName: true, userId: true },
      orderBy: { createdAt: 'asc' },
    });

    for (const instance of instances) {
      await this.configureInstanceWebhook(instance.instanceName, enabled);
    }

    console.log(
      `[WhatsApp][Webhook] Sincronización global completada. enabled=${enabled}, totalInstancias=${instances.length}`,
    );

    return { updated: instances.length, enabled };
  }

  async handleIncomingWebhook(instanceName: string, payload: unknown) {
    const record = await this.prisma.userWhatsappInstance.findUnique({
      where: { instanceName },
      select: { userId: true, instanceName: true },
    });

    if (!record) {
      console.warn(
        `[WhatsApp][Webhook] Webhook recibido para instancia no registrada "${instanceName}".`,
      );
      return { ok: true, ignored: true, reason: 'instance_not_registered' };
    }

    console.log(
      `[WhatsApp][Webhook] Evento recibido para instancia "${instanceName}" userId=${record.userId}: ${JSON.stringify(payload)}`,
    );

    return { ok: true };
  }

  private buildInstanceName(userId: string, custom?: string): string {
    const userSuffix = userId.replace(/-/g, '').substring(0, 16);
    const sanitizedCustom = (custom ?? '')
      .trim()
      .replace(/[^a-zA-Z0-9_-]/g, '_')
      .replace(/_+/g, '_')
      .replace(/^_+|_+$/g, '');

    if (sanitizedCustom.length >= 3) {
      const prefix = sanitizedCustom.substring(0, 40);
      return `${prefix}_${userSuffix}`;
    }

    // Auto-generate a unique instance name per user.
    return `user_${userSuffix}`;
  }

  private describeEvolutionError(error: unknown): string {
    if (error instanceof Error) {
      const code = (error as Error & { code?: string }).code;
      return code ? `${error.message} [${code}]` : error.message;
    }
    return String(error);
  }

  private isEvolutionUnavailableError(error: unknown): boolean {
    return error instanceof ServiceUnavailableException;
  }

  private async performEvolutionRequest(
    url: URL,
    init: { method?: string; headers?: Record<string, string>; body?: string },
  ): Promise<{ status: number; contentType: string; bodyText: string }> {
    const client = url.protocol === 'https:' ? https : http;

    return new Promise((resolve, reject) => {
      const req = client.request(
        url,
        {
          method: init.method ?? 'GET',
          headers: init.headers,
          family: 4,
          servername: url.hostname,
          timeout: this.requestTimeoutMs,
        },
        (res) => {
          const chunks: Buffer[] = [];
          res.on('data', (chunk) => chunks.push(Buffer.from(chunk)));
          res.on('end', () => {
            const bodyText = Buffer.concat(chunks).toString('utf8');
            resolve({
              status: res.statusCode ?? 0,
              contentType: Array.isArray(res.headers['content-type'])
                ? res.headers['content-type'].join(',')
                : (res.headers['content-type'] ?? ''),
              bodyText,
            });
          });
        },
      );

      req.on('timeout', () => {
        req.destroy(new Error(`Evolution API timeout after ${this.requestTimeoutMs}ms`));
      });
      req.on('error', reject);

      if (init.body) {
        req.write(init.body);
      }
      req.end();
    });
  }

  private async fetchEvolution<T = unknown>(
    path: string,
    options?: RequestInit,
  ): Promise<T> {
    const base = this.evolutionBaseUrl;
    if (!base) {
      throw new BadRequestException(
        'Evolution API no configurada. Falta EVOLUTION_API_URL en variables de entorno.',
      );
    }
    const url = `${base}${path}`;
    try {
      const response = await this.performEvolutionRequest(new URL(url), {
        method: options?.method,
        headers: {
          ...this.buildHeaders(),
          ...((options?.headers as Record<string, string> | undefined) ?? {}),
        },
        body: typeof options?.body === 'string' ? options.body : undefined,
      });

      let body: unknown;
      const contentType = response.contentType;
      if (contentType.includes('application/json')) {
        body = response.bodyText ? JSON.parse(response.bodyText) : null;
      } else {
        body = response.bodyText;
      }

      if (response.status < 200 || response.status >= 300) {
        const msg =
          typeof body === 'string'
            ? body.trim()
            : (body as { message?: string })?.message ?? `HTTP ${response.status}`;
        throw new BadRequestException(
          `Evolution API error (HTTP ${response.status}): ${msg}`,
        );
      }

      return body as T;
    } catch (error) {
      if (
        error instanceof BadRequestException ||
        error instanceof NotFoundException ||
        error instanceof ConflictException ||
        error instanceof ServiceUnavailableException
      ) {
        throw error;
      }

      const detail = this.describeEvolutionError(error);
      console.error(`[WhatsApp][Evolution] Request failed ${url}: ${detail}`);
      throw new ServiceUnavailableException(
        `No se pudo conectar con Evolution API. Verifica EVOLUTION_API_URL, DNS, SSL y conectividad saliente del contenedor API. Detalle: ${detail}`,
      );
    }
  }

  // ─── Instance management ────────────────────────────────────────────────

  async createInstance(userId: string, dto: CreateWhatsappInstanceDto) {
    const existing = await this.prisma.userWhatsappInstance.findUnique({
      where: { userId },
    });

    if (existing) {
      throw new ConflictException(
        'Este usuario ya tiene una instancia de WhatsApp registrada.',
      );
    }

    const instanceName = this.buildInstanceName(userId, dto.instanceName);
    const webhookEnabled = await this.isGlobalWebhookEnabled();

    // Create instance in Evolution API (if configured)
    if (this.evolutionBaseUrl) {
      try {
        await this.fetchEvolution(`/instance/create`, {
          method: 'POST',
          body: JSON.stringify({
            instanceName,
            qrcode: true,
            integration: 'WHATSAPP-BAILEYS',
            ...(dto.phoneNumber ? { number: dto.phoneNumber } : {}),
          }),
        });
      } catch (err) {
        // If Evolution API is not reachable, still save the record locally
        // so the user can retry QR fetching later
        const msg = err instanceof Error ? err.message : String(err);
        if (!msg.includes('Evolution API no configurada')) {
          // Log but don't block — instance record will be created as pending
          console.error(`[WhatsApp] createInstance Evolution error: ${msg}`);
        }
      }
    }

    const record = await this.prisma.userWhatsappInstance.create({
      data: {
        userId,
        instanceName,
        status: 'pending',
        ...(dto.phoneNumber ? { phoneNumber: dto.phoneNumber } : {}),
      },
    });

    await this.configureInstanceWebhook(instanceName, webhookEnabled);

    return record;
  }

  async getInstanceStatus(userId: string) {
    const record = await this.prisma.userWhatsappInstance.findUnique({
      where: { userId },
    });

    if (!record) {
      return { exists: false, status: null, instanceName: null, phoneNumber: null };
    }

    // Try to get live status from Evolution API
    if (this.evolutionBaseUrl && record.instanceName) {
      try {
        const data = await this.fetchEvolution<{
          instance?: { state?: string };
        }>(`/instance/connectionState/${encodeURIComponent(record.instanceName)}`);

        const state = data?.instance?.state ?? '';
        const isConnected = state === 'open';
        const newStatus = isConnected ? 'connected' : 'pending';

        if (newStatus !== record.status) {
          await this.prisma.userWhatsappInstance.update({
            where: { userId },
            data: { status: newStatus },
          });
          record.status = newStatus;
        }
      } catch (error) {
        console.warn(
          `[WhatsApp][status] No se pudo consultar estado en Evolution para "${record.instanceName}": ${this.describeEvolutionError(error)}`,
        );
        // Could not reach Evolution API — return stored status
      }
    }

    return {
      exists: true,
      status: record.status,
      instanceName: record.instanceName,
      phoneNumber: record.phoneNumber,
      id: record.id,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
    };
  }

  async getQrCode(userId: string) {
    console.log(`[WhatsApp][QR] Solicitando QR para userId=${userId}`);
    const record = await this.prisma.userWhatsappInstance.findUnique({
      where: { userId },
    });

    if (!record) {
      console.warn(`[WhatsApp][QR] Sin instancia registrada para userId=${userId}`);
      throw new NotFoundException(
        'No hay instancia de WhatsApp registrada. Crea una instancia primero.',
      );
    }

    if (!this.evolutionBaseUrl) {
      throw new BadRequestException(
        'Evolution API no configurada en el servidor.',
      );
    }

    // If already connected, no need to call /connect (it would return 400)
    if (record.status === 'connected') {
      console.log(`[WhatsApp][QR] Instancia "${record.instanceName}" ya conectada. No se solicita QR.`);
      return {
        instanceName: record.instanceName,
        qrBase64: '',
        status: 'connected',
      };
    }

    console.log(`[WhatsApp][QR] Intentando conectar instancia "${record.instanceName}" (status=${record.status})...`);

    type QrPayload = { base64?: string; code?: string; qrcode?: { base64?: string; code?: string } };

    const extractBase64 = (qrData: QrPayload) =>
      qrData?.base64 ?? qrData?.qrcode?.base64 ?? '';

    const tryConnect = () =>
      this.fetchEvolution<QrPayload>(
        `/instance/connect/${encodeURIComponent(record.instanceName)}`,
      );

    // First attempt
    try {
      const qrData = await tryConnect();
      console.log(`[WhatsApp][QR] QR obtenido para "${record.instanceName}" en primer intento.`);
      return {
        instanceName: record.instanceName,
        qrBase64: extractBase64(qrData),
        status: record.status,
      };
    } catch (firstErr) {
      if (this.isEvolutionUnavailableError(firstErr)) {
        console.error(
          `[WhatsApp][QR] Evolution no disponible al conectar "${record.instanceName}": ${this.describeEvolutionError(firstErr)}`,
        );
        throw firstErr;
      }

      // Instance likely doesn't exist in Evolution API (e.g. was never created
      // due to a prior network error). Try to recreate it, then retry.
      console.warn(
        `[WhatsApp] getQrCode first attempt failed for "${record.instanceName}", attempting recreation: ${firstErr instanceof Error ? firstErr.message : firstErr}`,
      );
      try {
        await this.fetchEvolution(`/instance/create`, {
          method: 'POST',
          body: JSON.stringify({
            instanceName: record.instanceName,
            qrcode: true,
            integration: 'WHATSAPP-BAILEYS',
            ...(record.phoneNumber ? { number: record.phoneNumber } : {}),
          }),
        });
        await this.configureInstanceWebhook(
          record.instanceName,
          await this.isGlobalWebhookEnabled(),
        );
      } catch (createErr) {
        if (this.isEvolutionUnavailableError(createErr)) {
          console.error(
            `[WhatsApp][QR] Evolution no disponible al recrear "${record.instanceName}": ${this.describeEvolutionError(createErr)}`,
          );
          throw createErr;
        }

        // If 409 (already exists), that's fine — continue to retry connect
        const msg =
          createErr instanceof Error ? createErr.message : String(createErr);
        if (!msg.includes('409') && !msg.toLowerCase().includes('already')) {
          console.error(`[WhatsApp][QR] Recreación de instancia fallida para "${record.instanceName}": ${msg}`);
          throw new BadRequestException(
            `No se pudo obtener el QR. Intenta eliminar y volver a crear la instancia.`,
          );
        }
        console.warn(`[WhatsApp][QR] Recreación: instancia "${record.instanceName}" ya existía (409), reintentando connect.`);
      }

      // Retry connect after recreation
      try {
        const qrData = await tryConnect();
        console.log(`[WhatsApp][QR] QR obtenido para "${record.instanceName}" luego de recreación.`);
        return {
          instanceName: record.instanceName,
          qrBase64: extractBase64(qrData),
          status: record.status,
        };
      } catch (retryErr) {
        if (this.isEvolutionUnavailableError(retryErr)) {
          console.error(
            `[WhatsApp][QR] Evolution no disponible en reintento para "${record.instanceName}": ${this.describeEvolutionError(retryErr)}`,
          );
          throw retryErr;
        }

        const msg =
          retryErr instanceof Error ? retryErr.message : String(retryErr);
        console.error(`[WhatsApp][QR] Fallo definitivo al obtener QR para "${record.instanceName}": ${msg}`);
        throw new BadRequestException(`No se pudo obtener el QR: ${msg}`);
      }
    }
  }

  async deleteInstance(userId: string) {
    const record = await this.prisma.userWhatsappInstance.findUnique({
      where: { userId },
    });

    if (!record) {
      throw new NotFoundException('No hay instancia de WhatsApp para eliminar.');
    }

    // Delete from Evolution API
    if (this.evolutionBaseUrl) {
      try {
        await this.fetchEvolution(
          `/instance/delete/${encodeURIComponent(record.instanceName)}`,
          { method: 'DELETE' },
        );
      } catch (err) {
        console.error(
          `[WhatsApp] deleteInstance Evolution error: ${err instanceof Error ? err.message : err}`,
        );
      }
    }

    await this.prisma.userWhatsappInstance.delete({ where: { userId } });
    return { deleted: true };
  }

  // ─── Admin ──────────────────────────────────────────────────────────────

  async listUsersWithWhatsappStatus() {
    const users = await this.prisma.user.findMany({
      select: {
        id: true,
        nombreCompleto: true,
        email: true,
        role: true,
        whatsappInstance: {
          select: {
            id: true,
            instanceName: true,
            status: true,
            phoneNumber: true,
            createdAt: true,
            updatedAt: true,
          },
        },
      },
      orderBy: { nombreCompleto: 'asc' },
    });

    return users.map((u) => ({
      id: u.id,
      nombreCompleto: u.nombreCompleto,
      email: u.email,
      role: u.role,
      whatsapp: u.whatsappInstance
        ? {
            id: u.whatsappInstance.id,
            instanceName: u.whatsappInstance.instanceName,
            status: u.whatsappInstance.status,
            phoneNumber: u.whatsappInstance.phoneNumber,
            createdAt: u.whatsappInstance.createdAt,
            updatedAt: u.whatsappInstance.updatedAt,
          }
        : null,
    }));
  }

  // ─── Send text message via Evolution API ────────────────────────────────

  async sendTextMessage(instanceName: string, remoteJid: string, text: string): Promise<unknown> {
    return this.fetchEvolution(`/message/sendText/${encodeURIComponent(instanceName)}`, {
      method: 'POST',
      body: JSON.stringify({
        number: remoteJid,
        text,
      }),
    });
  }
}
