import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma, Role } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CreateCotizacionDto, CreateCotizacionItemDto } from './dto/create-cotizacion.dto';
import { UpdateCotizacionDto } from './dto/update-cotizacion.dto';

@Injectable()
export class CotizacionesService {
  constructor(private readonly prisma: PrismaService) {}

  async list(user: { id: string; role: Role }, query: { customerPhone?: string; take?: number }) {
    const take = Math.min(Math.max(query.take ?? 80, 1), 500);
    const where: Prisma.CotizacionWhereInput = {};

    const customerPhone = query.customerPhone?.trim();
    if (customerPhone) where.customerPhone = customerPhone;

    // Non-admin users only see their own cotizaciones.
    if (user.role !== Role.ADMIN) {
      where.createdByUserId = user.id;
    }

    const items = await this.prisma.cotizacion.findMany({
      where,
      take,
      orderBy: { createdAt: 'desc' },
      include: { items: { orderBy: { createdAt: 'asc' } } },
    });

    return { items };
  }

  async findOne(user: { id: string; role: Role }, id: string) {
    const item = await this.prisma.cotizacion.findUnique({
      where: { id },
      include: { items: { orderBy: { createdAt: 'asc' } } },
    });

    if (!item) throw new NotFoundException('Cotización no encontrada');

    if (user.role !== Role.ADMIN && item.createdByUserId !== user.id) {
      throw new ForbiddenException('No puedes ver esta cotización');
    }

    return item;
  }

  async create(user: { id: string; role: Role }, dto: CreateCotizacionDto) {
    if (!dto.items?.length) {
      throw new BadRequestException('Agrega al menos un producto al ticket');
    }

    const customerPhone = dto.customerPhone.trim();
    const customerName = dto.customerName.trim();
    const note = (dto.note ?? '').trim();

    if (!customerPhone) throw new BadRequestException('Teléfono requerido');
    if (!customerName) throw new BadRequestException('Nombre de cliente requerido');

    const includeItbis = dto.includeItbis === true;
    const itbisRateRaw = dto.itbisRate ?? 0.18;
    const itbisRate = new Prisma.Decimal(Math.max(0, Math.min(itbisRateRaw, 1)));

    const normalized = await this.normalizeItems(dto.items);

    let subtotal = new Prisma.Decimal(0);
    for (const line of normalized) subtotal = subtotal.plus(line.lineTotal);

    const itbisAmount = includeItbis ? subtotal.mul(itbisRate) : new Prisma.Decimal(0);
    const total = subtotal.plus(itbisAmount);

    return this.prisma.$transaction(async (tx) => {
      const created = await tx.cotizacion.create({
        data: {
          createdByUserId: user.id,
          customerId: dto.customerId,
          customerName,
          customerPhone,
          note: note.length ? note : null,
          includeItbis,
          itbisRate,
          subtotal,
          itbisAmount,
          total,
          items: {
            create: normalized.map((item) => ({
              productId: item.productId,
              productNameSnapshot: item.productNameSnapshot,
              productImageSnapshot: item.productImageSnapshot,
              qty: item.qty,
              unitPrice: item.unitPrice,
              lineTotal: item.lineTotal,
            })),
          },
        },
        include: { items: { orderBy: { createdAt: 'asc' } } },
      });

      return created;
    });
  }

  async update(user: { id: string; role: Role }, id: string, dto: UpdateCotizacionDto) {
    const current = await this.prisma.cotizacion.findUnique({ where: { id } });
    if (!current) throw new NotFoundException('Cotización no encontrada');

    if (user.role !== Role.ADMIN && current.createdByUserId !== user.id) {
      throw new ForbiddenException('No puedes editar esta cotización');
    }

    const includeItbis = dto.includeItbis ?? current.includeItbis;
    const itbisRateRaw = dto.itbisRate ?? this.toNumber(current.itbisRate);
    const itbisRate = new Prisma.Decimal(Math.max(0, Math.min(itbisRateRaw, 1)));

    const nextItems = dto.items ? await this.normalizeItems(dto.items as CreateCotizacionItemDto[]) : null;

    let subtotal = new Prisma.Decimal(current.subtotal);
    let itbisAmount = new Prisma.Decimal(current.itbisAmount);
    let total = new Prisma.Decimal(current.total);

    if (nextItems) {
      subtotal = new Prisma.Decimal(0);
      for (const line of nextItems) subtotal = subtotal.plus(line.lineTotal);
      itbisAmount = includeItbis ? subtotal.mul(itbisRate) : new Prisma.Decimal(0);
      total = subtotal.plus(itbisAmount);
    }

    return this.prisma.$transaction(async (tx) => {
      if (nextItems) {
        await tx.cotizacionItem.deleteMany({ where: { cotizacionId: id } });
      }

      const updated = await tx.cotizacion.update({
        where: { id },
        data: {
          customerId: dto.customerId ?? current.customerId,
          customerName: dto.customerName ? dto.customerName.trim() : current.customerName,
          customerPhone: dto.customerPhone ? dto.customerPhone.trim() : current.customerPhone,
          note: dto.note !== undefined ? (dto.note?.trim().length ? dto.note.trim() : null) : current.note,
          includeItbis,
          itbisRate,
          subtotal,
          itbisAmount,
          total,
          items: nextItems
            ? {
                create: nextItems.map((item) => ({
                  productId: item.productId,
                  productNameSnapshot: item.productNameSnapshot,
                  productImageSnapshot: item.productImageSnapshot,
                  qty: item.qty,
                  unitPrice: item.unitPrice,
                  lineTotal: item.lineTotal,
                })),
              }
            : undefined,
        },
        include: { items: { orderBy: { createdAt: 'asc' } } },
      });

      return updated;
    });
  }

  async remove(user: { id: string; role: Role }, id: string) {
    const current = await this.prisma.cotizacion.findUnique({ where: { id } });
    if (!current) throw new NotFoundException('Cotización no encontrada');

    if (user.role !== Role.ADMIN && current.createdByUserId !== user.id) {
      throw new ForbiddenException('No puedes eliminar esta cotización');
    }

    await this.prisma.cotizacion.delete({ where: { id } });
    return { ok: true };
  }

  private async normalizeItems(items: CreateCotizacionItemDto[]) {
    const productIds = Array.from(new Set(items.map((i) => i.productId).filter((id): id is string => Boolean(id))));

    let products: Array<{ id: string; nombre: string; imagen: string | null }> = [];
    if (productIds.length) {
      products = await this.prisma.product.findMany({
        where: { id: { in: productIds } },
        select: { id: true, nombre: true, imagen: true },
      });
    }

    const productMap = new Map(products.map((p) => [p.id, p]));

    return items.map((item, index) => {
      const qty = new Prisma.Decimal(item.qty);
      const unitPrice = new Prisma.Decimal(item.unitPrice);

      if (qty.lte(0)) throw new BadRequestException(`Cantidad inválida en item #${index + 1}`);
      if (unitPrice.lt(0)) throw new BadRequestException(`Precio inválido en item #${index + 1}`);

      const productId = item.productId ?? null;
      const product = productId ? productMap.get(productId) : null;

      const productNameSnapshot = product?.nombre ?? item.productName?.trim();
      if (!productNameSnapshot) {
        throw new BadRequestException(`Nombre requerido en item #${index + 1}`);
      }

      const productImageSnapshot = product?.imagen ?? item.productImageSnapshot ?? null;
      const lineTotal = qty.mul(unitPrice);

      return {
        productId: product?.id ?? productId,
        productNameSnapshot,
        productImageSnapshot,
        qty,
        unitPrice,
        lineTotal,
      };
    });
  }

  private toNumber(value: Prisma.Decimal | number | string | null | undefined): number {
    if (value === null || value === undefined) return 0;
    if (typeof value === 'number') return value;
    return Number(value);
  }
}
