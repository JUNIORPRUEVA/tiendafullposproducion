import { Injectable, Logger, NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  classifyFullposImageValue,
  normalizeFullposCatalogImageUrl,
} from './fullpos-product-image.util';

type FullposIntegrationProduct = {
  id: string | number;
  sku?: string | null;
  barcode?: string | null;
  code?: string | null;
  codigo?: string | null;
  name?: string | null;
  nombre?: string | null;
  description?: string | null;
  descripcion?: string | null;
  details?: string | null;
  detail?: string | null;
  price?: number | string | null;
  precio?: number | string | null;
  cost?: number | string | null;
  costo?: number | string | null;
  stock?: number | string | null;
  quantity?: number | string | null;
  existencia?: number | string | null;
  category?: string | { name?: string | null; nombre?: string | null } | null;
  categoria?: string | { name?: string | null; nombre?: string | null } | null;
  category_name?: string | null;
  categoriaNombre?: string | null;
  image_url?: string | null;
  imageUrl?: string | null;
  imagen?: string | null;
  fotoUrl?: string | null;
  active?: boolean | null;
  is_active?: boolean | null;
  enabled?: boolean | null;
  status?: string | null;
  estado?: string | null;
  updated_at?: string | null;
  updatedAt?: string | null;
  modifiedAt?: string | null;
  created_at?: string | null;
  createdAt?: string | null;
};

type FullposListResponse = {
  items?: FullposIntegrationProduct[];
  data?: FullposIntegrationProduct[];
  products?: FullposIntegrationProduct[];
  rows?: FullposIntegrationProduct[];
  next_cursor?: string | null;
  nextCursor?: string | null;
};

type RemoteImageValidation = {
  isValid: boolean;
  checkedAt: number;
};

type CatalogProductView = {
  id: string;
  nombre: string;
  descripcion: string | null;
  codigo: string | null;
  precio: number;
  costo: number;
  stock: number | null;
  categoria: string | null;
  categoriaNombre: string | null;
  imagen: string | null;
  fotoUrl: string | null;
  activo: boolean;
  estado: string;
  createdAt: string | null;
  updatedAt: string | null;
  fechaActualizacion: string | null;
};

type CatalogProductsResponse = {
  source: 'FULLPOS';
  readOnly: true;
  total: number;
  fetchedAt: string;
  items: CatalogProductView[];
};

@Injectable()
export class CatalogProductsService {
  private readonly logger = new Logger(CatalogProductsService.name);
  private readonly fullposBaseUrl: string;
  private readonly fullposIntegrationToken: string;
  private readonly fullposTimeoutMs: number;
  private readonly remoteImageValidationCache = new Map<string, RemoteImageValidation>();

  constructor(private readonly config: ConfigService) {
    this.fullposBaseUrl = (config.get<string>('FULLPOS_INTEGRATION_BASE_URL') ?? '')
      .trim()
      .replace(/\/$/, '');
    this.fullposIntegrationToken = (config.get<string>('FULLPOS_INTEGRATION_TOKEN') ?? '').trim();
    this.fullposTimeoutMs = Number(config.get<string>('FULLPOS_INTEGRATION_TIMEOUT_MS') ?? 8000);
  }

  async findAll(): Promise<CatalogProductsResponse> {
    this.ensureConfigured();

    const rawItems = await this.fetchAllRawProducts();
    const imageStats = { empty: 0, relative: 0, absolute: 0 };

    const mapped = await Promise.all(
      rawItems.map(async (item) => {
        const rawImage = this.pickString(item.image_url, item.imageUrl, item.imagen, item.fotoUrl);
        imageStats[classifyFullposImageValue(rawImage)] += 1;
        return this.mapProduct(item, rawImage);
      }),
    );

    const activeItems = mapped.filter((item): item is CatalogProductView => item != null && item.activo);

    this.logger.log(
      `[catalog-products] source=FULLPOS raw=${rawItems.length} active=${activeItems.length} images(empty=${imageStats.empty},relative=${imageStats.relative},absolute=${imageStats.absolute})`,
    );

    return {
      source: 'FULLPOS',
      readOnly: true,
      total: activeItems.length,
      fetchedAt: new Date().toISOString(),
      items: activeItems,
    };
  }

  async findOne(id: string): Promise<CatalogProductView> {
    const response = await this.findAll();
    const found = response.items.find((item) => item.id === id);
    if (!found) {
      throw new NotFoundException('Product not found');
    }
    return found;
  }

  private ensureConfigured() {
    if (!this.fullposBaseUrl) {
      throw new ServiceUnavailableException('FULLPOS_INTEGRATION_BASE_URL no está configurado');
    }
    if (!this.fullposIntegrationToken) {
      throw new ServiceUnavailableException('FULLPOS_INTEGRATION_TOKEN no está configurado');
    }
  }

  private async fetchAllRawProducts(): Promise<FullposIntegrationProduct[]> {
    const items: FullposIntegrationProduct[] = [];
    let cursor: string | null = null;

    for (let page = 0; page < 50; page += 1) {
      const url = new URL(`${this.fullposBaseUrl}/api/integrations/products`);
      url.searchParams.set('limit', '500');
      if (cursor) {
        url.searchParams.set('cursor', cursor);
      }

      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), this.fullposTimeoutMs);

      try {
        const response = await fetch(url.toString(), {
          method: 'GET',
          headers: {
            Accept: 'application/json',
            Authorization: `Bearer ${this.fullposIntegrationToken}`,
          },
          signal: controller.signal,
        });

        if (!response.ok) {
          const text = await response.text().catch(() => '');
          this.logger.warn(
            `[catalog-products] upstream failed status=${response.status} body=${text.substring(0, 200)}`,
          );
          throw new ServiceUnavailableException('No se pudieron cargar productos desde FULLPOS');
        }

        const payload = (await response.json()) as FullposListResponse;
        const batch = this.extractRows(payload);
        items.push(...batch);
        cursor = payload.next_cursor ?? payload.nextCursor ?? null;
        if (!cursor) {
          break;
        }
      } finally {
        clearTimeout(timeout);
      }
    }

    return items;
  }

  private extractRows(payload: FullposListResponse): FullposIntegrationProduct[] {
    const candidates = [payload.items, payload.data, payload.products, payload.rows];
    for (const candidate of candidates) {
      if (Array.isArray(candidate)) {
        return candidate;
      }
    }
    return [];
  }

  private async mapProduct(
    item: FullposIntegrationProduct,
    rawImage: string | null,
  ): Promise<CatalogProductView | null> {
    const imageUrl = await this.validateFullposImageUrl(
      normalizeFullposCatalogImageUrl(rawImage, this.fullposBaseUrl),
    );
    const updatedAt = this.pickString(item.updated_at, item.updatedAt, item.modifiedAt);
    const categoria = this.extractCategory(item.category, item.categoria, item.category_name, item.categoriaNombre);
    const activo = this.resolveActive(item);
    const estado = activo ? 'ACTIVO' : 'INACTIVO';

    return {
      id: this.pickString(item.id)?.trim() ?? '',
      nombre: this.pickString(item.name, item.nombre) ?? 'Producto sin nombre',
      descripcion: this.pickString(item.description, item.descripcion, item.details, item.detail),
      codigo: this.pickString(item.sku, item.code, item.codigo, item.barcode),
      precio: this.asNumber(item.price, item.precio),
      costo: this.asNumber(item.cost, item.costo),
      stock: this.asNullableNumber(item.stock, item.quantity, item.existencia),
      categoria,
      categoriaNombre: categoria,
      imagen: imageUrl,
      fotoUrl: imageUrl,
      activo,
      estado,
      createdAt: this.pickString(item.created_at, item.createdAt),
      updatedAt,
      fechaActualizacion: updatedAt,
    };
  }

  private pickString(...values: unknown[]): string | null {
    for (const value of values) {
      if (value == null) continue;
      const text = String(value).trim();
      if (!text || text.toLowerCase() === 'null' || text.toLowerCase() === 'undefined') {
        continue;
      }
      return text;
    }
    return null;
  }

  private asNumber(...values: unknown[]): number {
    const value = this.asNullableNumber(...values);
    return value ?? 0;
  }

  private asNullableNumber(...values: unknown[]): number | null {
    for (const value of values) {
      if (value == null) continue;
      if (typeof value === 'number' && Number.isFinite(value)) {
        return value;
      }
      const parsed = Number(String(value).replace(',', '.').trim());
      if (Number.isFinite(parsed)) {
        return parsed;
      }
    }
    return null;
  }

  private extractCategory(...values: unknown[]): string | null {
    for (const value of values) {
      if (value == null) continue;
      if (typeof value === 'string') {
        const text = value.trim();
        if (text) return text;
        continue;
      }
      if (typeof value === 'object') {
        const candidate = value as { name?: unknown; nombre?: unknown };
        const text = this.pickString(candidate.name, candidate.nombre);
        if (text != null) return text;
      }
    }
    return null;
  }

  private resolveActive(item: FullposIntegrationProduct): boolean {
    const explicit = [item.active, item.is_active, item.enabled].find(
      (value) => typeof value === 'boolean',
    );
    if (typeof explicit === 'boolean') {
      return explicit;
    }

    const state = this.pickString(item.status, item.estado)?.toLowerCase();
    if (state == null) {
      return true;
    }

    return !['inactive', 'inactivo', 'disabled', 'archived', 'deleted'].includes(state);
  }

  private async validateFullposImageUrl(url: string | null): Promise<string | null> {
    const candidate = (url ?? '').trim();
    if (!candidate || !/^https?:\/\//i.test(candidate)) {
      return candidate || null;
    }

    let parsedUrl: URL;
    let fullposUrl: URL;
    try {
      parsedUrl = new URL(candidate);
      fullposUrl = new URL(this.fullposBaseUrl);
    } catch {
      return candidate;
    }

    const sameFullposHost = parsedUrl.host.toLowerCase() === fullposUrl.host.toLowerCase();
    const looksLikeUpload = parsedUrl.pathname.toLowerCase().includes('/uploads/');
    if (!sameFullposHost || !looksLikeUpload) {
      return candidate;
    }

    const cached = this.remoteImageValidationCache.get(candidate);
    const now = Date.now();
    if (cached) {
      const ttlMs = cached.isValid ? 30 * 60 * 1000 : 5 * 60 * 1000;
      if (now - cached.checkedAt < ttlMs) {
        return cached.isValid ? candidate : null;
      }
    }

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), Math.min(this.fullposTimeoutMs, 3000));

    try {
      let response = await fetch(candidate, {
        method: 'HEAD',
        headers: { Accept: 'image/*,*/*;q=0.8' },
        signal: controller.signal,
      });

      if (response.status === 405 || response.status === 501) {
        response = await fetch(candidate, {
          method: 'GET',
          headers: { Accept: 'image/*,*/*;q=0.8' },
          signal: controller.signal,
        });
      }

      const contentType = (response.headers.get('content-type') ?? '').toLowerCase();
      const isValid = response.ok && contentType.startsWith('image/');
      this.remoteImageValidationCache.set(candidate, {
        isValid,
        checkedAt: now,
      });
      if (!isValid) {
        this.logger.warn(`[catalog-products] omitting dead image status=${response.status} url=${candidate}`);
      }
      return isValid ? candidate : null;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.logger.warn(`[catalog-products] image validation failed url=${candidate} error=${message}`);
      this.remoteImageValidationCache.set(candidate, {
        isValid: false,
        checkedAt: now,
      });
      return null;
    } finally {
      clearTimeout(timeout);
    }
  }
}
