import { Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Prisma, Product } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CreateProductDto } from './dto/create-product.dto';
import { UpdateProductDto } from './dto/update-product.dto';

@Injectable()
export class ProductsService {
  private readonly publicBaseUrl: string;

  constructor(
    private readonly prisma: PrismaService,
    config: ConfigService
  ) {
    const base = config.get<string>('PUBLIC_BASE_URL') ?? config.get<string>('API_BASE_URL') ?? '';
    this.publicBaseUrl = base.trim().replace(/\/$/, '');
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
    return this.prisma.$transaction(async (tx) => {
      const data = {
        nombre: dto.nombre,
        categoria: dto.categoria,
        precio: new Prisma.Decimal(dto.precio),
        costo: new Prisma.Decimal(dto.costo),
        imagen: dto.fotoUrl,
      };

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
    await this.findOne(id);
    return this.prisma.$transaction(async (tx) => {
      const data = {
        nombre: dto.nombre,
        categoria: dto.categoria,
        precio: dto.precio === undefined ? undefined : new Prisma.Decimal(dto.precio),
        costo: dto.costo === undefined ? undefined : new Prisma.Decimal(dto.costo),
        imagen: dto.fotoUrl,
      };

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

}

