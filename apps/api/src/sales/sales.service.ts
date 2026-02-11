import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma, Sale } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CreateSaleDto } from './dto/create-sale.dto';

@Injectable()
export class SalesService {
  constructor(private readonly prisma: PrismaService) {}

  private toDecimal(value: number) {
    return new Prisma.Decimal(value);
  }

  async create(userId: string, dto: CreateSaleDto): Promise<Sale> {
    const cantidad = dto.cantidad ?? 1;
    if (cantidad < 1) throw new BadRequestException('cantidad must be >= 1');

    let puntosUtilidad: Prisma.Decimal;

    if (dto.productId) {
      const product = await this.prisma.product.findUnique({ where: { id: dto.productId } });
      if (!product) throw new NotFoundException('Product not found');
      puntosUtilidad = product.precio.sub(product.costo).mul(cantidad);
    } else {
      if (dto.puntosUtilidad === undefined) {
        throw new BadRequestException('puntosUtilidad is required when productId is missing');
      }
      puntosUtilidad = this.toDecimal(dto.puntosUtilidad);
    }

    const totalVenta = this.toDecimal(dto.totalVenta);
    const comision = totalVenta.mul(0.1);

    return this.prisma.sale.create({
      data: {
        userId,
        clientId: dto.clientId,
        productId: dto.productId,
        cantidad,
        totalVenta,
        puntosUtilidad,
        comision
      }
    });
  }

  private parseRange(from?: string, to?: string) {
    const where: any = {};
    if (from) {
      const d = new Date(from);
      if (Number.isNaN(d.getTime())) throw new BadRequestException('Invalid from');
      where.gte = d;
    }
    if (to) {
      const d = new Date(to);
      if (Number.isNaN(d.getTime())) throw new BadRequestException('Invalid to');
      d.setDate(d.getDate() + 1);
      where.lt = d;
    }
    return Object.keys(where).length ? where : undefined;
  }

  async listMine(userId: string, from?: string, to?: string) {
    const createdAt = this.parseRange(from, to);
    const where = {
      userId,
      ...(createdAt ? { createdAt } : {})
    } as any;

    const [items, summary] = await Promise.all([
      this.prisma.sale.findMany({ where, orderBy: { createdAt: 'desc' } }),
      this.prisma.sale.aggregate({
        where,
        _sum: { totalVenta: true, puntosUtilidad: true, comision: true }
      })
    ]);

    return {
      items,
      summary: {
        totalVendido: summary._sum.totalVenta?.toString() ?? '0',
        totalPuntos: summary._sum.puntosUtilidad?.toString() ?? '0',
        totalComision: summary._sum.comision?.toString() ?? '0'
      }
    };
  }

  async listAll(from?: string, to?: string) {
    const createdAt = this.parseRange(from, to);
    const where = createdAt ? ({ createdAt } as any) : undefined;

    const [items, summary] = await Promise.all([
      this.prisma.sale.findMany({ where, orderBy: { createdAt: 'desc' } }),
      this.prisma.sale.aggregate({
        where,
        _sum: { totalVenta: true, puntosUtilidad: true, comision: true }
      })
    ]);

    return {
      items,
      summary: {
        totalVendido: summary._sum.totalVenta?.toString() ?? '0',
        totalPuntos: summary._sum.puntosUtilidad?.toString() ?? '0',
        totalComision: summary._sum.comision?.toString() ?? '0'
      }
    };
  }
}

