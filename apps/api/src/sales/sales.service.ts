import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma, Role, SaleStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CreateSaleDto } from './dto/create-sale.dto';
import { CreateSaleItemDto } from './dto/create-sale-item.dto';
import { UpdateSaleDto } from './dto/update-sale.dto';
import { UpdateSaleItemDto } from './dto/update-sale-item.dto';
import { SalesQueryDto } from './dto/sales-query.dto';
import { AdminSalesQueryDto } from './dto/admin-sales-query.dto';

type CurrentUser = { id: string; role?: Role };

@Injectable()
export class SalesService {
  constructor(private readonly prisma: PrismaService) {}

  private toDecimal(value: number | string | Prisma.Decimal): Prisma.Decimal {
    if (value instanceof Prisma.Decimal) return value;
    return new Prisma.Decimal(value);
  }

  private isAdmin(user: CurrentUser) {
    return user.role === Role.ADMIN;
  }

  private parseRange(from?: string, to?: string) {
    const soldAt: Prisma.DateTimeFilter = {};
    if (from) {
      const d = new Date(from);
      if (Number.isNaN(d.getTime())) throw new BadRequestException('Invalid from date');
      soldAt.gte = d;
    }
    if (to) {
      const d = new Date(to);
      if (Number.isNaN(d.getTime())) throw new BadRequestException('Invalid to date');
      d.setDate(d.getDate() + 1);
      soldAt.lt = d;
    }
    return Object.keys(soldAt).length ? soldAt : undefined;
  }

  private buildSaleWhere(query: SalesQueryDto | AdminSalesQueryDto, sellerId?: string): Prisma.SaleWhereInput {
    const soldAt = this.parseRange(query.from, query.to);
    const where: Prisma.SaleWhereInput = {
      ...(soldAt ? { soldAt } : {}),
      ...(query.status ? { status: query.status } : {}),
      ...(query.clientId ? { clientId: query.clientId } : {}),
      ...(sellerId ? { sellerId } : {}),
      ...(query.productId
        ? {
            items: {
              some: { productId: query.productId }
            }
          }
        : {})
    };

    if ('role' in query && (query as AdminSalesQueryDto).role) {
      where.seller = { role: (query as AdminSalesQueryDto).role } as any;
    }

    return where;
  }

  private async assertSaleAccess(id: string, user: CurrentUser) {
    const sale = await this.prisma.sale.findUnique({ where: { id } });
    if (!sale) throw new NotFoundException('Sale not found');
    if (!this.isAdmin(user) && sale.sellerId !== user.id) {
      throw new ForbiddenException('No autorizado para esta venta');
    }
    return sale;
  }

  private async recalcSaleTotals(saleId: string) {
    const items = await this.prisma.saleItem.findMany({ where: { saleId } });
    const subtotal = items.reduce((acc, i) => acc.add(i.lineTotal), new Prisma.Decimal(0));
    const totalCost = items.reduce((acc, i) => acc.add(i.lineCost), new Prisma.Decimal(0));
    const profit = items.reduce((acc, i) => acc.add(i.lineProfit), new Prisma.Decimal(0));
    const commission = profit.greaterThan(0) ? profit.mul(0.1) : new Prisma.Decimal(0);

    await this.prisma.sale.update({
      where: { id: saleId },
      data: { subtotal, totalCost, profit, commission }
    });
  }

  private async addItemsInternal(saleId: string, items: CreateSaleItemDto[]) {
    if (!items.length) return;
    const productIds = [...new Set(items.map((i) => i.productId))];
    const products = await this.prisma.product.findMany({ where: { id: { in: productIds } } });
    const map = new Map(products.map((p) => [p.id, p]));

    for (const item of items) {
      const product = map.get(item.productId);
      if (!product) throw new NotFoundException('Product not found');
      const qty = item.qty ?? 1;
      if (qty < 1) throw new BadRequestException('qty must be >= 1');

      const unitPrice = this.toDecimal(item.unitPriceSold ?? product.precio);
      const unitCost = this.toDecimal(product.costo);
      const qtyDec = this.toDecimal(qty);
      const lineTotal = unitPrice.mul(qtyDec);
      const lineCost = unitCost.mul(qtyDec);
      const lineProfit = lineTotal.sub(lineCost);

      await this.prisma.saleItem.create({
        data: {
          saleId,
          productId: product.id,
          qty,
          unitPriceSold: unitPrice,
          unitCostSnapshot: unitCost,
          lineTotal,
          lineCost,
          lineProfit
        }
      });
    }
  }

  async createSale(user: CurrentUser, dto: CreateSaleDto) {
    const sale = await this.prisma.sale.create({
      data: {
        sellerId: user.id,
        clientId: dto.clientId,
        status: dto.status ?? SaleStatus.DRAFT,
        note: dto.note?.trim() || null,
        subtotal: new Prisma.Decimal(0),
        totalCost: new Prisma.Decimal(0),
        profit: new Prisma.Decimal(0),
        commission: new Prisma.Decimal(0)
      }
    });

    if (dto.items?.length) {
      await this.addItemsInternal(sale.id, dto.items);
    }

    await this.recalcSaleTotals(sale.id);
    return this.findByIdForUser(user, sale.id);
  }

  async addItem(user: CurrentUser, saleId: string, dto: CreateSaleItemDto) {
    await this.assertSaleAccess(saleId, user);
    await this.addItemsInternal(saleId, [dto]);
    await this.recalcSaleTotals(saleId);
    return this.findByIdForUser(user, saleId);
  }

  async updateItem(user: CurrentUser, saleId: string, itemId: string, dto: UpdateSaleItemDto) {
    await this.assertSaleAccess(saleId, user);
    const item = await this.prisma.saleItem.findUnique({ where: { id: itemId } });
    if (!item || item.saleId !== saleId) throw new NotFoundException('Sale item not found');

    const qty = dto.qty ?? item.qty;
    if (qty < 1) throw new BadRequestException('qty must be >= 1');

    const unitPrice = dto.unitPriceSold !== undefined ? this.toDecimal(dto.unitPriceSold) : item.unitPriceSold;
    const qtyDec = this.toDecimal(qty);
    const lineTotal = unitPrice.mul(qtyDec);
    const lineCost = item.unitCostSnapshot.mul(qtyDec);
    const lineProfit = lineTotal.sub(lineCost);

    await this.prisma.saleItem.update({
      where: { id: itemId },
      data: { qty, unitPriceSold: unitPrice, lineTotal, lineCost, lineProfit }
    });

    await this.recalcSaleTotals(saleId);
    return this.findByIdForUser(user, saleId);
  }

  async removeItem(user: CurrentUser, saleId: string, itemId: string) {
    await this.assertSaleAccess(saleId, user);
    const item = await this.prisma.saleItem.findUnique({ where: { id: itemId } });
    if (!item || item.saleId !== saleId) throw new NotFoundException('Sale item not found');

    await this.prisma.saleItem.delete({ where: { id: itemId } });
    await this.recalcSaleTotals(saleId);
    return this.findByIdForUser(user, saleId);
  }

  async updateSale(user: CurrentUser, saleId: string, dto: UpdateSaleDto) {
    await this.assertSaleAccess(saleId, user);
    const data: Prisma.SaleUpdateInput = {};

    if (dto.clientId !== undefined) {
      data.client = dto.clientId ? { connect: { id: dto.clientId } } : { disconnect: true };
    }
    if (dto.note !== undefined) {
      data.note = dto.note?.trim() || null;
    }
    if (dto.status !== undefined) {
      data.status = dto.status;
    }

    await this.prisma.sale.update({ where: { id: saleId }, data });
    await this.recalcSaleTotals(saleId);
    return this.findByIdForUser(user, saleId);
  }

  async deleteSale(user: CurrentUser, saleId: string) {
    const sale = await this.assertSaleAccess(saleId, user);
    if (!this.isAdmin(user) && sale.status !== SaleStatus.DRAFT) {
      throw new BadRequestException('Solo se pueden borrar ventas en borrador');
    }
    await this.prisma.sale.delete({ where: { id: saleId } });
    return { ok: true };
  }

  private readonly saleInclude = {
    client: true,
    seller: true,
    items: { include: { product: true } }
  } as const;

  async findByIdForUser(user: CurrentUser, saleId: string) {
    const sale = await this.prisma.sale.findUnique({ where: { id: saleId }, include: this.saleInclude });
    if (!sale) throw new NotFoundException('Sale not found');
    if (!this.isAdmin(user) && sale.sellerId !== user.id) {
      throw new ForbiddenException('No autorizado para esta venta');
    }
    return sale;
  }

  async listMine(user: CurrentUser, query: SalesQueryDto) {
    const where = this.buildSaleWhere(query, user.id);
    const [items, summary] = await Promise.all([
      this.prisma.sale.findMany({ where, orderBy: { soldAt: 'desc' }, include: this.saleInclude }),
      this.prisma.sale.aggregate({ where, _count: { id: true }, _sum: { subtotal: true, totalCost: true, profit: true, commission: true } })
    ]);

    return {
      items,
      summary: {
        count: summary._count.id,
        totalRevenue: summary._sum.subtotal?.toString() ?? '0',
        totalCost: summary._sum.totalCost?.toString() ?? '0',
        totalProfit: summary._sum.profit?.toString() ?? '0',
        totalCommission: summary._sum.commission?.toString() ?? '0'
      }
    };
  }

  async adminList(query: AdminSalesQueryDto) {
    const where = this.buildSaleWhere(query, query.sellerId);
    const [items, summary] = await Promise.all([
      this.prisma.sale.findMany({ where, orderBy: { soldAt: 'desc' }, include: this.saleInclude }),
      this.prisma.sale.aggregate({ where, _count: { id: true }, _sum: { subtotal: true, totalCost: true, profit: true, commission: true } })
    ]);

    return {
      items,
      summary: {
        count: summary._count.id,
        totalRevenue: summary._sum.subtotal?.toString() ?? '0',
        totalCost: summary._sum.totalCost?.toString() ?? '0',
        totalProfit: summary._sum.profit?.toString() ?? '0',
        totalCommission: summary._sum.commission?.toString() ?? '0'
      }
    };
  }

  async adminSummary(query: AdminSalesQueryDto) {
    const where = this.buildSaleWhere(query, query.sellerId);

    const saleFilter = where && Object.keys(where).length ? { sale: { is: where } } : undefined;

    const [summary, topSellersRaw, topProductsRaw] = await Promise.all([
      this.prisma.sale.aggregate({ where, _count: { id: true }, _sum: { subtotal: true, totalCost: true, profit: true, commission: true } }),
      this.prisma.sale.groupBy({
        by: ['sellerId'],
        where,
        _sum: { subtotal: true, profit: true, commission: true },
        orderBy: { _sum: { profit: 'desc' } },
        take: 5
      }),
      this.prisma.saleItem.groupBy({
        by: ['productId'],
        where: saleFilter,
        _sum: { lineTotal: true, lineProfit: true, lineCost: true, qty: true },
        orderBy: { _sum: { lineProfit: 'desc' } },
        take: 5
      })
    ]);

    const sellerIds = topSellersRaw.map((s) => s.sellerId);
    const sellers = sellerIds.length
      ? await this.prisma.user.findMany({ where: { id: { in: sellerIds } }, select: { id: true, nombreCompleto: true, email: true } })
      : [];

    const productIds = topProductsRaw.map((p) => p.productId);
    const products = productIds.length
      ? await this.prisma.product.findMany({ where: { id: { in: productIds } }, select: { id: true, nombre: true } })
      : [];

    const topSellers = topSellersRaw.map((s) => {
      const seller = sellers.find((u) => u.id === s.sellerId);
      return {
        sellerId: s.sellerId,
        sellerName: seller?.nombreCompleto ?? 'N/D',
        sellerEmail: seller?.email ?? '',
        revenue: s._sum.subtotal?.toString() ?? '0',
        profit: s._sum.profit?.toString() ?? '0',
        commission: s._sum.commission?.toString() ?? '0'
      };
    });

    const topProducts = topProductsRaw.map((p) => {
      const product = products.find((prod) => prod.id === p.productId);
      return {
        productId: p.productId,
        productName: product?.nombre ?? 'N/D',
        revenue: p._sum.lineTotal?.toString() ?? '0',
        profit: p._sum.lineProfit?.toString() ?? '0',
        cost: p._sum.lineCost?.toString() ?? '0',
        qty: p._sum.qty ?? 0
      };
    });

    return {
      totalSalesCount: summary._count.id,
      totalRevenue: summary._sum.subtotal?.toString() ?? '0',
      totalCost: summary._sum.totalCost?.toString() ?? '0',
      totalProfit: summary._sum.profit?.toString() ?? '0',
      totalCommission: summary._sum.commission?.toString() ?? '0',
      topSellers,
      topProducts
    };
  }
}

