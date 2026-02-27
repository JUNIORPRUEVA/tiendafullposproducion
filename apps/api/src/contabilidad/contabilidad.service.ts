import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import {
  CloseType,
  DepositOrderStatus,
  PayableFrequency,
  Prisma,
} from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CreateCloseDto, UpdateCloseDto } from './close.dto';
import {
  CreateDepositOrderDto,
  DepositOrdersQueryDto,
} from './deposit-order.dto';
import {
  CreateFiscalInvoiceDto,
  FiscalInvoicesQueryDto,
  UpdateFiscalInvoiceDto,
} from './fiscal-invoice.dto';
import {
  CreatePayableServiceDto,
  PayablePaymentsQueryDto,
  PayableServicesQueryDto,
  RegisterPayablePaymentDto,
  UpdatePayableServiceDto,
} from './payable.dto';

type Actor = { id?: string; role?: 'ADMIN' | 'ASISTENTE' };

type GetClosesQuery = {
  date?: string;
  from?: string;
  to?: string;
  type?: string;
};

@Injectable()
export class ContabilidadService {
  constructor(private prisma: PrismaService) {}

  private toNullableTrimmed(value?: string | null) {
    const cleaned = (value ?? '').trim();
    return cleaned.length > 0 ? cleaned : null;
  }

  private addMonthsKeepingDay(input: Date, months: number) {
    const source = new Date(input);
    const targetYear = source.getFullYear();
    const targetMonth = source.getMonth() + months;
    const safe = new Date(targetYear, targetMonth + 1, 0);
    const safeDay = Math.min(source.getDate(), safe.getDate());

    return new Date(
      targetYear,
      targetMonth,
      safeDay,
      source.getHours(),
      source.getMinutes(),
      source.getSeconds(),
      source.getMilliseconds(),
    );
  }

  private addDays(input: Date, days: number) {
    const next = new Date(input);
    next.setDate(next.getDate() + days);
    return next;
  }

  private nextDueDateFrom(frequency: PayableFrequency, paidAt: Date) {
    switch (frequency) {
      case PayableFrequency.MONTHLY:
        return this.addMonthsKeepingDay(paidAt, 1);
      case PayableFrequency.BIWEEKLY:
        return this.addDays(paidAt, 15);
      case PayableFrequency.ONE_TIME:
      default:
        return paidAt;
    }
  }

  private readonly allowedTransferBanks = new Set([
    'POPULAR',
    'BANRESERVAS',
    'BHD',
    'OTRO',
  ]);

  private isAdmin(actor: Actor) {
    return actor.role === 'ADMIN';
  }

  private isAssistant(actor: Actor) {
    return actor.role === 'ASISTENTE';
  }

  private isSameLocalDay(a: Date, b: Date) {
    return (
      a.getFullYear() === b.getFullYear() &&
      a.getMonth() === b.getMonth() &&
      a.getDate() === b.getDate()
    );
  }

  private normalizeRoleGuard(actor: Actor) {
    if (!actor.id) {
      throw new ForbiddenException('No autorizado para operar cierres');
    }
  }

  private parseType(value?: string): CloseType | undefined {
    if (!value) return undefined;
    const normalized = value.trim().toUpperCase();
    if (normalized === 'CAPSULAS') return CloseType.CAPSULAS;
    if (normalized === 'POS') return CloseType.POS;
    if (normalized === 'TIENDA') return CloseType.TIENDA;
    return undefined;
  }

  private normalizeDayRange(input: Date) {
    const start = new Date(input);
    start.setHours(0, 0, 0, 0);
    const end = new Date(input);
    end.setHours(23, 59, 59, 999);
    return { start, end };
  }

  private normalizeTransferBank(value?: string | null) {
    const cleaned = (value ?? '').trim();
    if (cleaned.length == 0) return null;

    const normalized = cleaned.toUpperCase();
    if (this.allowedTransferBanks.has(normalized)) {
      return normalized;
    }

    return cleaned;
  }

  private validateTransferData(transfer: number, transferBank?: string | null) {
    if (transfer <= 0) {
      return;
    }

    const cleaned = (transferBank ?? '').trim();
    if (cleaned.length === 0) {
      throw new BadRequestException(
        'Cuando hay transferencia debes indicar banco y monto',
      );
    }
  }

  async createClose(dto: CreateCloseDto, actor: Actor) {
    this.normalizeRoleGuard(actor);

    const creator = await this.prisma.user.findUnique({
      where: { id: actor.id! },
      select: { nombreCompleto: true },
    });

    this.validateTransferData(dto.transfer, dto.transferBank);
    const normalizedTransferBank = this.normalizeTransferBank(dto.transferBank);

    return this.prisma.close.create({
      data: {
        type: dto.type,
        date: dto.date ? new Date(dto.date) : new Date(),
        status: dto.status,
        cash: dto.cash,
        transfer: dto.transfer,
        transferBank: normalizedTransferBank,
        card: dto.card,
        expenses: dto.expenses,
        cashDelivered: dto.cashDelivered,
        createdById: actor.id!,
        createdByName: creator?.nombreCompleto ?? null,
      },
    });
  }

  async getCloses(query: GetClosesQuery) {
    const where: Record<string, unknown> = {};

    if (query.date) {
      const { start, end } = this.normalizeDayRange(new Date(query.date));
      where.date = { gte: start, lte: end };
    } else if (query.from || query.to) {
      const from = query.from ? new Date(query.from) : null;
      const to = query.to ? new Date(query.to) : null;
      if (from || to) {
        where.date = {
          ...(from != null ? { gte: from } : {}),
          ...(to != null ? { lte: to } : {}),
        };
      }
    }

    const type = this.parseType(query.type);
    if (type) {
      where.type = type;
    }

    return this.prisma.close.findMany({
      where,
      orderBy: [{ date: 'desc' }, { createdAt: 'desc' }],
    });
  }

  async getCloseById(id: string) {
    return this.prisma.close.findUnique({
      where: { id },
    });
  }

  async updateClose(id: string, dto: UpdateCloseDto, actor: Actor) {
    this.normalizeRoleGuard(actor);

    const close = await this.prisma.close.findUnique({ where: { id } });
    if (!close) throw new NotFoundException('Cierre no encontrado');

    if (this.isAssistant(actor)) {
      const isOwner = close.createdById === actor.id;
      const isToday = this.isSameLocalDay(new Date(close.createdAt), new Date());
      if (!isOwner || !isToday) {
        throw new ForbiddenException(
          'El asistente solo puede editar cierres propios creados el mismo día',
        );
      }
    }

    const nextTransfer = dto.transfer ?? Number(close.transfer);
    const nextTransferBankRaw = dto.transferBank ?? close.transferBank;
    this.validateTransferData(nextTransfer, nextTransferBankRaw);
    const normalizedTransferBank =
      nextTransfer > 0 ? this.normalizeTransferBank(nextTransferBankRaw) : null;

    return this.prisma.close.update({
      where: { id },
      data: {
        ...dto,
        transferBank: dto.transfer == null && dto.transferBank == null
            ? undefined
            : normalizedTransferBank,
      },
    });
  }

  async deleteClose(id: string, actor: Actor) {
    this.normalizeRoleGuard(actor);

    const close = await this.prisma.close.findUnique({ where: { id } });
    if (!close) throw new NotFoundException('Cierre no encontrado');

    if (!this.isAdmin(actor)) {
      const isOwner = close.createdById === actor.id;
      const isToday = this.isSameLocalDay(new Date(close.createdAt), new Date());
      if (!isOwner || !isToday) {
        throw new ForbiddenException(
          'El asistente solo puede borrar cierres propios creados el mismo día',
        );
      }
    }

    return this.prisma.close.delete({
      where: { id },
    });
  }

  async createDepositOrder(dto: CreateDepositOrderDto, actor: Actor) {
    this.normalizeRoleGuard(actor);

    const creator = await this.prisma.user.findUnique({
      where: { id: actor.id! },
      select: { nombreCompleto: true },
    });

    return this.prisma.depositOrder.create({
      data: {
        windowFrom: new Date(dto.windowFrom),
        windowTo: new Date(dto.windowTo),
        bankName: dto.bankName.trim(),
        reserveAmount: dto.reserveAmount,
        totalAvailableCash: dto.totalAvailableCash,
        depositTotal: dto.depositTotal,
        closesCountByType: dto.closesCountByType,
        depositByType: dto.depositByType,
        accountByType: dto.accountByType,
        status: DepositOrderStatus.PENDING,
        createdById: actor.id!,
        createdByName: creator?.nombreCompleto ?? null,
      },
    });
  }

  async getDepositOrders(query: DepositOrdersQueryDto) {
    const where: Record<string, unknown> = {};

    if (query.from || query.to) {
      const from = query.from ? new Date(query.from) : null;
      const to = query.to ? new Date(query.to) : null;
      where.windowFrom = {
        ...(from != null ? { gte: from } : {}),
        ...(to != null ? { lte: to } : {}),
      };
    }

    if (query.status) {
      where.status = query.status;
    }

    return this.prisma.depositOrder.findMany({
      where,
      orderBy: [{ createdAt: 'desc' }],
    });
  }

  async createFiscalInvoice(dto: CreateFiscalInvoiceDto, actor: Actor) {
    this.normalizeRoleGuard(actor);

    const creator = await this.prisma.user.findUnique({
      where: { id: actor.id! },
      select: { nombreCompleto: true },
    });

    return this.prisma.fiscalInvoice.create({
      data: {
        kind: dto.kind,
        invoiceDate: new Date(dto.invoiceDate),
        imageUrl: dto.imageUrl.trim(),
        note: dto.note?.trim() || null,
        createdById: actor.id!,
        createdByName: creator?.nombreCompleto ?? null,
      },
    });
  }

  async getFiscalInvoices(query: FiscalInvoicesQueryDto) {
    const where: Record<string, unknown> = {};

    if (query.kind) {
      where.kind = query.kind;
    }

    if (query.from || query.to) {
      const from = query.from ? new Date(query.from) : null;
      const to = query.to ? new Date(query.to) : null;

      where.invoiceDate = {
        ...(from != null ? { gte: from } : {}),
        ...(to != null ? { lte: to } : {}),
      };
    }

    return this.prisma.fiscalInvoice.findMany({
      where,
      orderBy: [{ invoiceDate: 'desc' }, { createdAt: 'desc' }],
    });
  }

  async updateFiscalInvoice(id: string, dto: UpdateFiscalInvoiceDto, actor: Actor) {
    this.normalizeRoleGuard(actor);

    const existing = await this.prisma.fiscalInvoice.findUnique({ where: { id } });
    if (!existing) throw new NotFoundException('Factura fiscal no encontrada');

    return this.prisma.fiscalInvoice.update({
      where: { id },
      data: {
        ...(dto.kind != null ? { kind: dto.kind } : {}),
        ...(dto.invoiceDate != null ? { invoiceDate: new Date(dto.invoiceDate) } : {}),
        ...(dto.imageUrl != null ? { imageUrl: dto.imageUrl.trim() } : {}),
        ...(dto.note != null ? { note: dto.note.trim() || null } : {}),
      },
    });
  }

  async deleteFiscalInvoice(id: string, actor: Actor) {
    this.normalizeRoleGuard(actor);

    const existing = await this.prisma.fiscalInvoice.findUnique({ where: { id } });
    if (!existing) throw new NotFoundException('Factura fiscal no encontrada');

    return this.prisma.fiscalInvoice.delete({ where: { id } });
  }

  async createPayableService(dto: CreatePayableServiceDto, actor: Actor) {
    this.normalizeRoleGuard(actor);

    const creator = await this.prisma.user.findUnique({
      where: { id: actor.id! },
      select: { nombreCompleto: true },
    });

    return this.prisma.payableService.create({
      data: {
        title: dto.title.trim(),
        providerKind: dto.providerKind,
        providerName: dto.providerName.trim(),
        description: this.toNullableTrimmed(dto.description),
        frequency: dto.frequency,
        defaultAmount: dto.defaultAmount,
        nextDueDate: new Date(dto.nextDueDate),
        active: dto.active ?? true,
        createdById: actor.id!,
        createdByName: creator?.nombreCompleto ?? null,
      },
      include: {
        payments: {
          orderBy: [{ paidAt: 'desc' }, { createdAt: 'desc' }],
        },
      },
    });
  }

  async getPayableServices(query: PayableServicesQueryDto) {
    const where: Prisma.PayableServiceWhereInput = {};

    if (query.active != null) {
      where.active = query.active;
    }

    return this.prisma.payableService.findMany({
      where,
      include: {
        payments: {
          orderBy: [{ paidAt: 'desc' }, { createdAt: 'desc' }],
        },
      },
      orderBy: [{ active: 'desc' }, { nextDueDate: 'asc' }, { createdAt: 'desc' }],
    });
  }

  async updatePayableService(id: string, dto: UpdatePayableServiceDto, actor: Actor) {
    this.normalizeRoleGuard(actor);

    const existing = await this.prisma.payableService.findUnique({ where: { id } });
    if (!existing) {
      throw new NotFoundException('Servicio por pagar no encontrado');
    }

    return this.prisma.payableService.update({
      where: { id },
      data: {
        ...(dto.title != null ? { title: dto.title.trim() } : {}),
        ...(dto.providerKind != null ? { providerKind: dto.providerKind } : {}),
        ...(dto.providerName != null ? { providerName: dto.providerName.trim() } : {}),
        ...(dto.description != null ? { description: this.toNullableTrimmed(dto.description) } : {}),
        ...(dto.frequency != null ? { frequency: dto.frequency } : {}),
        ...(dto.defaultAmount != null ? { defaultAmount: dto.defaultAmount } : {}),
        ...(dto.nextDueDate != null ? { nextDueDate: new Date(dto.nextDueDate) } : {}),
        ...(dto.active != null ? { active: dto.active } : {}),
      },
      include: {
        payments: {
          orderBy: [{ paidAt: 'desc' }, { createdAt: 'desc' }],
        },
      },
    });
  }

  async registerPayablePayment(
    serviceId: string,
    dto: RegisterPayablePaymentDto,
    actor: Actor,
  ) {
    this.normalizeRoleGuard(actor);

    const service = await this.prisma.payableService.findUnique({
      where: { id: serviceId },
    });

    if (!service) {
      throw new NotFoundException('Servicio por pagar no encontrado');
    }

    const creator = await this.prisma.user.findUnique({
      where: { id: actor.id! },
      select: { nombreCompleto: true },
    });

    const paidAt = dto.paidAt ? new Date(dto.paidAt) : new Date();
    const nextDueDate = this.nextDueDateFrom(service.frequency, paidAt);

    const result = await this.prisma.$transaction(async (tx) => {
      const payment = await tx.payablePayment.create({
        data: {
          serviceId: service.id,
          amount: dto.amount,
          paidAt,
          note: this.toNullableTrimmed(dto.note),
          createdById: actor.id!,
          createdByName: creator?.nombreCompleto ?? null,
        },
      });

      await tx.payableService.update({
        where: { id: service.id },
        data: {
          lastPaidAt: paidAt,
          nextDueDate,
          active: service.frequency === PayableFrequency.ONE_TIME ? false : true,
        },
      });

      return payment;
    });

    return this.prisma.payablePayment.findUnique({
      where: { id: result.id },
      include: {
        service: true,
      },
    });
  }

  async getPayablePayments(query: PayablePaymentsQueryDto) {
    const where: Prisma.PayablePaymentWhereInput = {};

    if (query.serviceId) {
      where.serviceId = query.serviceId;
    }

    if (query.from || query.to) {
      where.paidAt = {
        ...(query.from ? { gte: new Date(query.from) } : {}),
        ...(query.to ? { lte: new Date(query.to) } : {}),
      };
    }

    return this.prisma.payablePayment.findMany({
      where,
      include: {
        service: true,
      },
      orderBy: [{ paidAt: 'desc' }, { createdAt: 'desc' }],
    });
  }
}