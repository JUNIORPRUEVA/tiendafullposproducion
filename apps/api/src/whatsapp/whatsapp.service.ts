import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
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

  private buildInstanceName(userId: string, custom?: string): string {
    if (custom && custom.trim().length >= 3) {
      // Sanitize: only alphanumeric, hyphens, underscores
      return custom.trim().replace(/[^a-zA-Z0-9_-]/g, '_');
    }
    // Auto-generate a name based on userId prefix
    return `user_${userId.replace(/-/g, '').substring(0, 16)}`;
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
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.requestTimeoutMs);
    try {
      const res = await fetch(url, {
        ...options,
        headers: {
          ...this.buildHeaders(),
          ...(options?.headers ?? {}),
        },
        signal: controller.signal,
      });

      let body: unknown;
      const contentType = res.headers.get('content-type') ?? '';
      if (contentType.includes('application/json')) {
        body = await res.json();
      } else {
        body = await res.text();
      }

      if (!res.ok) {
        const msg =
          typeof body === 'string'
            ? body.trim()
            : (body as { message?: string })?.message ?? `HTTP ${res.status}`;
        throw new BadRequestException(
          `Evolution API error (HTTP ${res.status}): ${msg}`,
        );
      }

      return body as T;
    } finally {
      clearTimeout(timer);
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
      } catch {
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
      } catch (createErr) {
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
}
