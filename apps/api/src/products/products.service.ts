import { Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Category, Prisma, Product } from '@prisma/client';
import type { Prisma as PrismaNS } from '@prisma/client';
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

  create(dto: CreateProductDto): Promise<Product> {
    return this.prisma.$transaction(async (tx) => {
      const category = await this.findOrCreateCategory(tx, dto.categoria);
      const product = await tx.product.create({
        data: {
          nombre: dto.nombre,
          precio: new Prisma.Decimal(dto.precio),
          costo: new Prisma.Decimal(dto.costo),
          fotoUrl: dto.fotoUrl,
          categoryId: category?.id,
        },
        include: { category: true },
      });
      return this.mapProduct(product);
    });
  }

  async findAll(): Promise<any[]> {
    const products = await this.prisma.product.findMany({ orderBy: { createdAt: 'desc' }, include: { category: true } });
    return products.map(this.mapProduct);
  }

  async findOne(id: string): Promise<any> {
    const product = await this.prisma.product.findUnique({ where: { id }, include: { category: true } });
    if (!product) throw new NotFoundException('Product not found');
    return this.mapProduct(product);
  }

  async update(id: string, dto: UpdateProductDto): Promise<any> {
    await this.findOne(id);
    return this.prisma.$transaction(async (tx) => {
      let categoryId: string | undefined;
      if (dto.categoria) {
        const category = await this.findOrCreateCategory(tx, dto.categoria);
        categoryId = category?.id;
      }
      const updated = await tx.product.update({
        where: { id },
        data: {
          nombre: dto.nombre,
          precio: dto.precio === undefined ? undefined : new Prisma.Decimal(dto.precio),
          costo: dto.costo === undefined ? undefined : new Prisma.Decimal(dto.costo),
          fotoUrl: dto.fotoUrl,
          categoryId,
        },
        include: { category: true },
      });
      return this.mapProduct(updated);
    });
  }

  async remove(id: string) {
    await this.findOne(id);
    await this.prisma.product.delete({ where: { id } });
    return { ok: true };
  }

  private mapProduct(product: Product & { category?: Category | null }) {
    const fotoUrl = this.resolveUrl(product.fotoUrl ?? null);
    return {
      ...product,
      fotoUrl,
      categoriaNombre: product.category?.nombre,
    };
  }

  private resolveUrl(url: string | null): string | null {
    if (!url) return null;
    if (/^https?:\/\//i.test(url)) return url;
    if (!this.publicBaseUrl) return url;
    const normalized = url.startsWith('/') ? url : `/${url}`;
    return `${this.publicBaseUrl}${normalized}`;
  }

  private async findOrCreateCategory(tx: PrismaNS.TransactionClient, nombre: string) {
    const trimmed = nombre.trim();
    if (!trimmed) return null;
    const existing = await tx.category.findUnique({ where: { nombre: trimmed } });
    if (existing) return existing;
    return tx.category.create({ data: { nombre: trimmed } });
  }
}

