import { ConflictException, Injectable, Logger, NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Prisma, Product } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CreateProductDto } from './dto/create-product.dto';
import { UpdateProductDto } from './dto/update-product.dto';

type ProductsSource = 'FULLPOS' | 'LOCAL';

type FullposIntegrationProduct = {
  id: number;
  sku: string;
  barcode: string;
  name: string;
  price: number;
  cost: number;
  stock: number;
  image_url?: string | null;
  active: boolean;
  updated_at: string;
};

type FullposListResponse = {
  items: FullposIntegrationProduct[];
  next_cursor: string | null;
};

@Injectable()
export class ProductsService {
  private readonly logger = new Logger(ProductsService.name);
  private readonly publicBaseUrl: string;
  private readonly productsSource: ProductsSource;
  private readonly fullposBaseUrl: string;
  private readonly fullposIntegrationToken: string;
  private readonly fullposTimeoutMs: number;

  constructor(
    private readonly prisma: PrismaService,
    config: ConfigService
  ) {
    const base = config.get<string>('PUBLIC_BASE_URL') ?? config.get<string>('API_BASE_URL') ?? '';
    this.publicBaseUrl = base.trim().replace(/\/$/, '');

    const rawSource = (config.get<string>('PRODUCTS_SOURCE') ?? '').trim().toUpperCase();
    const nodeEnv = (config.get<string>('NODE_ENV') ?? process.env.NODE_ENV ?? 'development').toLowerCase();
    const defaultSource: ProductsSource = nodeEnv === 'production' ? 'LOCAL' : 'FULLPOS';
    this.productsSource = rawSource === 'LOCAL' || rawSource === 'FULLPOS' ? (rawSource as ProductsSource) : defaultSource;

    this.fullposBaseUrl = (config.get<string>('FULLPOS_INTEGRATION_BASE_URL') ?? '').trim().replace(/\/$/, '');
    this.fullposIntegrationToken = (config.get<string>('FULLPOS_INTEGRATION_TOKEN') ?? '').trim();
    this.fullposTimeoutMs = Number(config.get<string>('FULLPOS_INTEGRATION_TIMEOUT_MS') ?? 8000);
  }

  isReadOnly() {
    return this.productsSource === 'FULLPOS';
  }

  getSource(): ProductsSource {
    return this.productsSource;
  }

  private assertWritable() {
    if (this.productsSource === 'FULLPOS') {
      throw new ConflictException('Productos en modo solo-lectura: fuente FULLPOS (cloud). Administra productos en FULLPOS.');
    }
  }

  private ensureFullposConfigured() {
    if (!this.fullposBaseUrl) {
      throw new ServiceUnavailableException('FULLPOS_INTEGRATION_BASE_URL no está configurado');
    }
    if (!this.fullposIntegrationToken) {
      throw new ServiceUnavailableException('FULLPOS_INTEGRATION_TOKEN no está configurado');
    }
  }

  private async fetchFullposProducts(): Promise<any[]> {
    this.ensureFullposConfigured();

    const items: FullposIntegrationProduct[] = [];
    let cursor: string | null = null;

    for (let page = 0; page < 50; page += 1) {
      const url = new URL(`${this.fullposBaseUrl}/api/integrations/products`);
      url.searchParams.set('limit', '500');
      if (cursor) url.searchParams.set('cursor', cursor);

      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), this.fullposTimeoutMs);

      try {
        const res = await fetch(url.toString(), {
          method: 'GET',
          headers: {
            Accept: 'application/json',
            Authorization: `Bearer ${this.fullposIntegrationToken}`,
          },
          signal: controller.signal,
        });

        if (!res.ok) {
          const text = await res.text().catch(() => '');
          this.logger.warn(`FULLPOS integrations/products failed: status=${res.status} body=${text.substring(0, 200)}`);
          throw new ServiceUnavailableException('No se pudieron cargar productos desde FULLPOS');
        }

        const data = (await res.json()) as FullposListResponse;
        const batch = Array.isArray(data?.items) ? data.items : [];
        items.push(...batch);
        cursor = data?.next_cursor ?? null;
        if (!cursor) break;
      } finally {
        clearTimeout(timeout);
      }
    }

    return items.map((p) => ({
      id: String(p.id),
      nombre: p.name,
      categoria: null,
      categoriaNombre: null,
      precio: p.price,
      costo: p.cost,
      imagen: p.image_url ?? null,
      fotoUrl: p.image_url ?? null,
      createdAt: null,
      updatedAt: p.updated_at,
    }));
  }

  private isSchemaMismatch(error: unknown) {
    if (error instanceof Prisma.PrismaClientKnownRequestError) {
      return error.code === 'P2021' || error.code === 'P2022';
    }

    if (typeof error === 'object' && error !== null) {
      const value = error as { code?: unknown; message?: unknown };
      const code = typeof value.code === 'string' ? value.code : '';
      const message = typeof value.message === 'string' ? value.message : '';
      return (
        code === 'P2021' ||
        code === 'P2022' ||
        message.includes('does not exist in the current database') ||
        message.toLowerCase().includes('column')
      );
    }

    return false;
  }

  create(dto: CreateProductDto): Promise<Product> {
    this.assertWritable();
    return this.prisma.$transaction(async (tx) => {
      const normalizedImagePath = this.normalizeImagePathForStorage(dto.fotoUrl);
      const data = {
        nombre: dto.nombre,
        categoria: dto.categoria,
        precio: new Prisma.Decimal(dto.precio),
        costo: new Prisma.Decimal(dto.costo),
        imagen: normalizedImagePath,
      };

      if (dto.fotoUrl !== normalizedImagePath) {
        this.logger.log(`normalize create image path: "${dto.fotoUrl ?? ''}" -> "${normalizedImagePath ?? ''}"`);
      }

      try {
        const product = await tx.product.create({ data });
        return this.mapProduct(product);
      } catch (error) {
        if (!this.isSchemaMismatch(error)) throw error;
        const product = await tx.product.create({ data });
        return this.mapProduct(product);
      }
    });
  }

  async findAll(): Promise<any[]> {
    if (this.productsSource === 'FULLPOS') {
      return this.fetchFullposProducts();
    }

    try {
      const products = await this.prisma.product.findMany({ orderBy: { nombre: 'asc' } });
      return products.map((p) => this.mapProduct(p));
    } catch (error) {
      if (!this.isSchemaMismatch(error)) throw error;
      const products = await this.prisma.product.findMany({ orderBy: { nombre: 'asc' } });
      return products.map((p) => this.mapProduct(p));
    }
  }

  async findOne(id: string): Promise<any> {
    if (this.productsSource === 'FULLPOS') {
      const items = await this.fetchFullposProducts();
      const found = items.find((p) => `${p.id}` === `${id}`);
      if (!found) throw new NotFoundException('Product not found');
      return found;
    }

    let product: Product | null = null;
    try {
      product = await this.prisma.product.findUnique({ where: { id } });
    } catch (error) {
      if (!this.isSchemaMismatch(error)) throw error;
      product = await this.prisma.product.findUnique({ where: { id } });
    }
    if (!product) throw new NotFoundException('Product not found');
    return this.mapProduct(product);
  }

  async update(id: string, dto: UpdateProductDto): Promise<any> {
    this.assertWritable();
    await this.findOne(id);
    return this.prisma.$transaction(async (tx) => {
      const normalizedImagePath = dto.fotoUrl === undefined
        ? undefined
        : this.normalizeImagePathForStorage(dto.fotoUrl);
      const data = {
        nombre: dto.nombre,
        categoria: dto.categoria,
        precio: dto.precio === undefined ? undefined : new Prisma.Decimal(dto.precio),
        costo: dto.costo === undefined ? undefined : new Prisma.Decimal(dto.costo),
        imagen: normalizedImagePath,
      };

      if (dto.fotoUrl !== undefined && dto.fotoUrl !== normalizedImagePath) {
        this.logger.log(`normalize update image path: "${dto.fotoUrl}" -> "${normalizedImagePath ?? ''}"`);
      }

      try {
        const updated = await tx.product.update({ where: { id }, data });
        return this.mapProduct(updated);
      } catch (error) {
        if (!this.isSchemaMismatch(error)) throw error;
        const updated = await tx.product.update({ where: { id }, data });
        return this.mapProduct(updated);
      }
    });
  }

  async remove(id: string) {
    this.assertWritable();
    await this.findOne(id);
    await this.prisma.product.delete({ where: { id } });
    return { ok: true };
  }

  private mapProduct(product: Product) {
    const fotoUrl = this.resolveUrl(product.imagen ?? null);
    return {
      ...product,
      fotoUrl,
      categoria: product.categoria ?? null,
      categoriaNombre: product.categoria ?? null,
    };
  }

  private resolveUrl(url: string | null): string | null {
    if (!url) return null;

    const extractUploadsPath = (value: string): string | null => {
      const normalized = value.replace(/\\/g, '/').trim();
      const marker = '/uploads/';
      const markerIndex = normalized.indexOf(marker);
      if (markerIndex >= 0) {
        return normalized.substring(markerIndex);
      }
      if (normalized.startsWith('uploads/')) {
        return `/${normalized}`;
      }
      if (normalized.startsWith('./uploads/')) {
        return normalized.substring(1);
      }
      return null;
    };

    if (/^https?:\/\//i.test(url)) {
      if (!this.publicBaseUrl) return url;

      try {
        const parsed = new URL(url);
        const publicHost = new URL(this.publicBaseUrl).host.toLowerCase();
        const currentHost = parsed.host.toLowerCase();
        const normalizedPath = extractUploadsPath(parsed.pathname);
        const isUploadsPath = normalizedPath != null;

        if (isUploadsPath && currentHost !== publicHost) {
          const query = parsed.search ?? '';
          return `${this.publicBaseUrl}${normalizedPath}${query}`;
        }
      } catch {
        return url;
      }

      return url;
    }

    const uploadsPath = extractUploadsPath(url);
    if (uploadsPath) {
      if (!this.publicBaseUrl) return uploadsPath;
      return `${this.publicBaseUrl}${uploadsPath}`;
    }

    if (!this.publicBaseUrl) return url;
    const normalized = url.startsWith('/') ? url : `/${url}`;
    return `${this.publicBaseUrl}${normalized}`;
  }

  private normalizeImagePathForStorage(raw?: string | null): string | null {
    if (raw === undefined || raw === null) return null;

    const extractUploadsPath = (value: string): string | null => {
      const normalized = value.replace(/\\/g, '/').trim();
      const marker = '/uploads/';
      const markerIndex = normalized.indexOf(marker);
      if (markerIndex >= 0) {
        return normalized.substring(markerIndex);
      }
      if (normalized.startsWith('uploads/')) {
        return `/${normalized}`;
      }
      if (normalized.startsWith('./uploads/')) {
        return normalized.substring(1);
      }
      return null;
    };

    const value = raw.trim();
    if (!value) return null;

    if (/^https?:\/\//i.test(value)) {
      try {
        const parsed = new URL(value);
        const uploadsPath = extractUploadsPath(parsed.pathname);
        if (uploadsPath) return uploadsPath;
        return null;
      } catch {
        return null;
      }
    }

    const uploadsPath = extractUploadsPath(value);
    if (uploadsPath) return uploadsPath;

    return null;
  }

}

