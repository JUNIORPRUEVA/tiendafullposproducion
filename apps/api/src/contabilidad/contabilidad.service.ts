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
import { ConfigService } from '@nestjs/config';
import PDFDocument from 'pdfkit';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { R2Service } from '../storage/r2.service';
import {
  CloseStatus,
  CloseTransferEntryDto,
  CreateCloseDto,
  UpdateCloseDto,
} from './close.dto';
import {
  CreateDepositOrderDto,
  DepositOrdersQueryDto,
  DepositOrderStatusDto,
  UpdateDepositOrderDto,
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

type Actor = { id?: string; role?: string };

type GetClosesQuery = {
  date?: string;
  from?: string;
  to?: string;
  type?: string;
};

@Injectable()
export class ContabilidadService {
  constructor(
    private prisma: PrismaService,
    private readonly r2: R2Service,
    private readonly notifications: NotificationsService,
    private readonly config: ConfigService,
  ) {}

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

  private normalizeRoleGuard(actor: Actor) {
    if (!actor.id) {
      throw new ForbiddenException('No autorizado para operar cierres');
    }
  }

  private ensureAdmin(actor: Actor) {
    this.normalizeRoleGuard(actor);
    if ((actor.role ?? '').toUpperCase() !== 'ADMIN') {
      throw new ForbiddenException(
        'Solo administración puede editar o eliminar depósitos',
      );
    }
  }

  private ensureReviewer(actor: Actor) {
    this.normalizeRoleGuard(actor);
    const role = (actor.role ?? '').toUpperCase();
    if (role !== 'ADMIN' && role !== 'ASISTENTE') {
      throw new ForbiddenException(
        'Solo administraciÃ³n o contabilidad puede revisar cierres',
      );
    }
  }

  private isReviewer(actor: Actor) {
    const role = (actor.role ?? '').toUpperCase();
    return role === 'ADMIN' || role === 'ASISTENTE';
  }

  private accountingDay(input: Date) {
    const value = new Date(input);
    value.setHours(0, 0, 0, 0);
    return value;
  }

  private parseType(value?: string): CloseType | undefined {
    if (!value) return undefined;
    const normalized = value.trim().toUpperCase();
    if (normalized === 'CAPSULAS') return CloseType.CAPSULAS;
    if (normalized === 'POS') return CloseType.POS;
    if (normalized === 'TIENDA') return CloseType.TIENDA;
    if (normalized === 'PHYTOEMAGRY' || normalized === 'PHYTO')
      return CloseType.PHYTOEMAGRY;
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

  private decimal(value: unknown) {
    const n =
      typeof value === 'number'
        ? value
        : value instanceof Prisma.Decimal
          ? value.toNumber()
          : Number(value ?? 0);
    if (!Number.isFinite(n) || n < 0) {
      throw new BadRequestException(
        'Los montos del cierre no pueden ser negativos.',
      );
    }
    return Math.round(n * 100) / 100;
  }

  private roundMoney(value: number) {
    if (!Number.isFinite(value)) {
      throw new BadRequestException('Monto invÃ¡lido.');
    }
    return Math.round(value * 100) / 100;
  }

  private normalizeTransfers(transfers?: CloseTransferEntryDto[]) {
    return (transfers ?? []).map((entry, index) => {
      const bankName = this.toNullableTrimmed(entry.bankName);
      if (!bankName) {
        throw new BadRequestException(
          `La transferencia #${index + 1} requiere banco.`,
        );
      }
      const amount = this.decimal(entry.amount);
      if (amount <= 0) {
        throw new BadRequestException(
          `La transferencia #${index + 1} requiere monto mayor a cero.`,
        );
      }
      const vouchers = entry.vouchers ?? [];
      if (vouchers.length === 0) {
        throw new BadRequestException(
          `La transferencia #${index + 1} requiere al menos un voucher.`,
        );
      }
      return {
        bankName,
        amount,
        referenceNumber: this.toNullableTrimmed(entry.referenceNumber),
        note: this.toNullableTrimmed(entry.note),
        vouchers: vouchers.map((voucher, voucherIndex) => {
          const storageKey = this.toNullableTrimmed(voucher.storageKey);
          const fileUrl = this.toNullableTrimmed(voucher.fileUrl);
          const fileName = this.toNullableTrimmed(voucher.fileName);
          const mimeType = this.toNullableTrimmed(voucher.mimeType);
          if (!storageKey || !fileUrl || !fileName || !mimeType) {
            throw new BadRequestException(
              `El voucher #${voucherIndex + 1} de la transferencia #${index + 1} no tiene datos completos.`,
            );
          }
          return { storageKey, fileUrl, fileName, mimeType };
        }),
      };
    });
  }

  private calculateCloseTotals(params: {
    cash: number;
    transfers: Array<{ amount: number }>;
    card: number;
    otherIncome: number;
    expenses: number;
    cashDelivered: number;
  }) {
    const transfer = params.transfers.reduce(
      (sum, item) => sum + item.amount,
      0,
    );
    const totalIncome =
      params.cash + transfer + params.card + params.otherIncome;
    const netTotal = totalIncome - params.expenses;
    const difference = params.cash - params.cashDelivered;
    return {
      transfer: this.decimal(transfer),
      totalIncome: this.decimal(totalIncome),
      netTotal: this.roundMoney(netTotal),
      difference: this.roundMoney(difference),
    };
  }

  private async findCloseOrThrow(id: string) {
    const close = await this.prisma.close.findUnique({
      where: { id },
      include: {
        transfers: {
          include: { vouchers: true },
          orderBy: { createdAt: 'asc' },
        },
      },
    });
    if (!close) throw new NotFoundException('Cierre no encontrado');
    return close;
  }

  async createClose(dto: CreateCloseDto, actor: Actor) {
    this.normalizeRoleGuard(actor);

    const creator = await this.prisma.user.findUnique({
      where: { id: actor.id! },
      select: { nombreCompleto: true },
    });

    const transfers = this.normalizeTransfers(dto.transfers);
    const cash = this.decimal(dto.cash);
    const card = this.decimal(dto.card);
    const otherIncome = this.decimal(dto.otherIncome ?? 0);
    const expenses = this.decimal(dto.expenses);
    const cashDelivered = this.decimal(dto.cashDelivered);
    const totals = this.calculateCloseTotals({
      cash,
      transfers,
      card,
      otherIncome,
      expenses,
      cashDelivered,
    });
    const date = this.accountingDay(new Date(dto.date));
    const existing = await this.prisma.close.findFirst({
      where: { type: dto.type, date, status: { not: CloseStatus.REJECTED } },
      select: { id: true },
    });
    if (existing) {
      throw new BadRequestException(
        'Ya existe un cierre activo para esta unidad de negocio en esa fecha.',
      );
    }

    const close = await this.prisma.close.create({
      data: {
        type: dto.type,
        date,
        status: CloseStatus.PENDING,
        cash,
        transfer: totals.transfer,
        transferBank: transfers.map((item) => item.bankName).join(', ') || null,
        card,
        otherIncome,
        expenses,
        cashDelivered,
        totalIncome: totals.totalIncome,
        netTotal: totals.netTotal,
        difference: totals.difference,
        notes: this.toNullableTrimmed(dto.notes),
        evidenceUrl: this.toNullableTrimmed(dto.evidenceUrl),
        evidenceFileName: this.toNullableTrimmed(dto.evidenceFileName),
        createdById: actor.id!,
        createdByName: creator?.nombreCompleto ?? null,
        transfers: {
          create: transfers.map((entry) => ({
            bankName: entry.bankName,
            amount: entry.amount,
            referenceNumber: entry.referenceNumber,
            note: entry.note,
            vouchers: { create: entry.vouchers },
          })),
        },
      },
      include: { transfers: { include: { vouchers: true } } },
    });

    return this.afterCloseSubmitted(close.id);
  }

  async getCloses(query: GetClosesQuery, actor?: Actor) {
    const where: Record<string, unknown> = {};
    if (actor?.id && !this.isReviewer(actor)) {
      where.createdById = actor.id;
    }

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
      include: {
        transfers: {
          include: { vouchers: true },
          orderBy: { createdAt: 'asc' },
        },
      },
    });
  }

  async getCloseById(id: string, actor?: Actor) {
    const close = await this.findCloseOrThrow(id);
    if (
      actor?.id &&
      !this.isReviewer(actor) &&
      close.createdById !== actor.id
    ) {
      throw new ForbiddenException('No puedes ver cierres de otro usuario.');
    }
    return close;
  }

  async updateClose(id: string, dto: UpdateCloseDto, actor: Actor) {
    this.normalizeRoleGuard(actor);

    const close = await this.prisma.close.findUnique({ where: { id } });
    if (!close) throw new NotFoundException('Cierre no encontrado');
    if (!this.isReviewer(actor) && close.createdById !== actor.id) {
      throw new ForbiddenException('No puedes editar cierres de otro usuario.');
    }
    if (
      close.status === CloseStatus.APPROVED ||
      close.status === CloseStatus.REJECTED
    ) {
      throw new BadRequestException(
        'Este cierre ya fue revisado y no se puede editar.',
      );
    }

    const transfers =
      dto.transfers === undefined
        ? await this.prisma.closeTransfer
            .findMany({ where: { closeId: id }, select: { amount: true } })
            .then((items) =>
              items.map((item) => ({ amount: Number(item.amount) })),
            )
        : this.normalizeTransfers(dto.transfers);
    const cash = this.decimal(dto.cash ?? close.cash);
    const card = this.decimal(dto.card ?? close.card);
    const otherIncome = this.decimal(dto.otherIncome ?? close.otherIncome);
    const expenses = this.decimal(dto.expenses ?? close.expenses);
    const cashDelivered = this.decimal(
      dto.cashDelivered ?? close.cashDelivered,
    );
    const totals = this.calculateCloseTotals({
      cash,
      transfers,
      card,
      otherIncome,
      expenses,
      cashDelivered,
    });

    return this.prisma.close.update({
      where: { id },
      data: {
        cash,
        card,
        otherIncome,
        expenses,
        cashDelivered,
        transfer: totals.transfer,
        totalIncome: totals.totalIncome,
        netTotal: totals.netTotal,
        difference: totals.difference,
        notes:
          dto.notes === undefined
            ? undefined
            : this.toNullableTrimmed(dto.notes),
        evidenceUrl:
          dto.evidenceUrl === undefined
            ? undefined
            : this.toNullableTrimmed(dto.evidenceUrl),
        evidenceFileName:
          dto.evidenceFileName === undefined
            ? undefined
            : this.toNullableTrimmed(dto.evidenceFileName),
        transferBank:
          dto.transfers === undefined
            ? undefined
            : this.normalizeTransfers(dto.transfers)
                .map((item) => item.bankName)
                .join(', ') || null,
        ...(dto.transfers === undefined
          ? {}
          : {
              transfers: {
                deleteMany: {},
                create: this.normalizeTransfers(dto.transfers).map((entry) => ({
                  bankName: entry.bankName,
                  amount: entry.amount,
                  referenceNumber: entry.referenceNumber,
                  note: entry.note,
                  vouchers: { create: entry.vouchers },
                })),
              },
            }),
      },
      include: { transfers: { include: { vouchers: true } } },
    });
  }

  async deleteClose(id: string, actor: Actor) {
    this.normalizeRoleGuard(actor);

    const close = await this.prisma.close.findUnique({ where: { id } });
    if (!close) throw new NotFoundException('Cierre no encontrado');

    throw new BadRequestException(
      'Los cierres diarios no se eliminan. Rechaza el registro para conservar la trazabilidad.',
    );
  }

  async reviewClose(id: string, status: CloseStatus, actor: Actor) {
    this.ensureReviewer(actor);
    if (status !== CloseStatus.APPROVED && status !== CloseStatus.REJECTED) {
      throw new BadRequestException('Estado de revisiÃ³n invÃ¡lido');
    }

    const close = await this.prisma.close.findUnique({ where: { id } });
    if (!close) throw new NotFoundException('Cierre no encontrado');
    if (close.status !== CloseStatus.PENDING) {
      throw new BadRequestException(
        'Solo los cierres pendientes se pueden revisar.',
      );
    }

    const reviewer = await this.prisma.user.findUnique({
      where: { id: actor.id! },
      select: { nombreCompleto: true },
    });

    return this.prisma.close.update({
      where: { id },
      data: {
        status,
        reviewedById: actor.id!,
        reviewedByName: reviewer?.nombreCompleto ?? null,
        reviewedAt: new Date(),
      },
    });
  }

  async reviewCloseWithNote(
    id: string,
    status: CloseStatus,
    actor: Actor,
    reviewNote?: string | null,
  ) {
    const reviewed = await this.reviewClose(id, status, actor);
    return this.prisma.close.update({
      where: { id: reviewed.id },
      data: { reviewNote: this.toNullableTrimmed(reviewNote) },
      include: { transfers: { include: { vouchers: true } } },
    });
  }

  private async afterCloseSubmitted(closeId: string) {
    const close = await this.findCloseOrThrow(closeId);
    const pdf = await this.generateClosePdf(close);
    const yyyy = close.date.getUTCFullYear();
    const mm = String(close.date.getUTCMonth() + 1).padStart(2, '0');
    const objectKey = `contabilidad/daily-closes/${yyyy}/${mm}/${close.id}/${pdf.fileName}`;
    await this.r2.putObject({
      objectKey,
      body: pdf.bytes,
      contentType: 'application/pdf',
    });
    const pdfUrl = this.r2.buildPublicUrl(objectKey);

    await this.prisma.close.update({
      where: { id: close.id },
      data: {
        pdfStorageKey: objectKey,
        pdfUrl,
        pdfFileName: pdf.fileName,
        notificationStatus: 'pending',
        notificationError: null,
      },
    });

    await this.enqueueCloseNotifications(
      close.id,
      pdf.bytes,
      pdf.fileName,
      pdfUrl,
    );
    return this.findCloseOrThrow(close.id);
  }

  private money(value: unknown) {
    const n =
      value instanceof Prisma.Decimal ? value.toNumber() : Number(value ?? 0);
    return new Intl.NumberFormat('es-DO', {
      style: 'currency',
      currency: 'DOP',
      minimumFractionDigits: 2,
    }).format(Number.isFinite(n) ? n : 0);
  }

  private dateLabel(value: Date) {
    return new Intl.DateTimeFormat('es-DO', {
      dateStyle: 'medium',
      timeStyle: 'short',
    }).format(value);
  }

  private async generateClosePdf(
    close: Awaited<ReturnType<ContabilidadService['findCloseOrThrow']>>,
  ) {
    const appConfig = await this.prisma.appConfig.findUnique({
      where: { id: 'global' },
      select: { companyName: true, rnc: true, phone: true, address: true },
    });
    const companyName = appConfig?.companyName?.trim() || 'FULLTECH';
    const doc = new PDFDocument({ margin: 42, size: 'A4' });
    const chunks: Buffer[] = [];
    const bytesPromise = new Promise<Buffer>((resolve, reject) => {
      doc.on('data', (chunk) => chunks.push(Buffer.from(chunk)));
      doc.on('end', () => resolve(Buffer.concat(chunks)));
      doc.on('error', reject);
    });

    const line = (label: string, value: string, x = 42, width = 500) => {
      doc
        .font('Helvetica-Bold')
        .text(`${label}: `, x, doc.y, { continued: true });
      doc.font('Helvetica').text(value, { width });
    };
    const section = (title: string) => {
      doc.moveDown(0.8);
      doc.fontSize(13).font('Helvetica-Bold').fillColor('#0f172a').text(title);
      doc
        .moveTo(42, doc.y + 3)
        .lineTo(553, doc.y + 3)
        .strokeColor('#d1d5db')
        .stroke();
      doc.moveDown(0.6);
    };

    doc.rect(0, 0, 595, 92).fill('#0f5b6b');
    doc
      .fillColor('#ffffff')
      .fontSize(20)
      .font('Helvetica-Bold')
      .text(companyName, 42, 28);
    doc.fontSize(11).font('Helvetica').text('Cierre Diario', 42, 55);
    doc.fillColor('#0f172a');
    doc.y = 116;

    section('Datos generales');
    line(
      'Unidad',
      close.type === CloseType.PHYTOEMAGRY ? 'PhytoEmagry' : 'Tienda',
    );
    line('Fecha cierre', new Intl.DateTimeFormat('es-DO').format(close.date));
    line('Creado por', close.createdByName ?? close.createdById ?? 'N/D');
    line('Creado en', this.dateLabel(close.createdAt));
    line('Estado', close.status);

    section('Totales');
    const totalRows = [
      ['Efectivo', this.money(close.cash)],
      ['Transferencias', this.money(close.transfer)],
      ['Tarjeta', this.money(close.card)],
      ['Otros ingresos', this.money(close.otherIncome)],
      ['Gastos', this.money(close.expenses)],
      ['Total ingresos', this.money(close.totalIncome)],
      ['Total neto', this.money(close.netTotal)],
      ['Efectivo entregado', this.money(close.cashDelivered)],
      ['Diferencia', this.money(close.difference)],
    ];
    for (const [label, value] of totalRows) line(label, value);

    section('Transferencias');
    if (close.transfers.length === 0) {
      doc.font('Helvetica').text('Sin transferencias declaradas.');
    } else {
      close.transfers.forEach((transfer, index) => {
        doc
          .font('Helvetica-Bold')
          .text(
            `${index + 1}. ${transfer.bankName} - ${this.money(transfer.amount)}`,
          );
        if (transfer.referenceNumber)
          doc.font('Helvetica').text(`Referencia: ${transfer.referenceNumber}`);
        if (transfer.note) doc.font('Helvetica').text(`Nota: ${transfer.note}`);
        transfer.vouchers.forEach((voucher) => {
          doc
            .font('Helvetica')
            .fillColor('#0f5b6b')
            .text(`Voucher: ${voucher.fileName} - ${voucher.fileUrl}`);
          doc.fillColor('#0f172a');
        });
        doc.moveDown(0.4);
      });
    }

    section('Auditoria');
    line('Revisado por', close.reviewedByName ?? close.reviewedById ?? 'N/D');
    line(
      'Revisado en',
      close.reviewedAt ? this.dateLabel(close.reviewedAt) : 'N/D',
    );
    line('Nota revision', close.reviewNote ?? 'N/D');
    if (close.aiReportSummary) {
      line('Riesgo IA', close.aiRiskLevel ?? 'N/D');
      line('Resumen IA', close.aiReportSummary);
    }
    if (close.notes) {
      section('Notas');
      doc.font('Helvetica').text(close.notes, { width: 500 });
    }

    doc.end();
    const bytes = await bytesPromise;
    return {
      bytes,
      fileName: `cierre_diario_${close.type}_${close.date.toISOString().slice(0, 10)}_${close.id.slice(0, 8)}.pdf`,
    };
  }

  private buildCloseAdminMessage(
    close: Awaited<ReturnType<ContabilidadService['findCloseOrThrow']>>,
    pdfUrl: string,
  ) {
    return [
      'Cierre diario pendiente',
      `Unidad: ${close.type === CloseType.PHYTOEMAGRY ? 'PhytoEmagry' : 'Tienda'}`,
      `Fecha: ${new Intl.DateTimeFormat('es-DO').format(close.date)}`,
      `Creado por: ${close.createdByName ?? close.createdById ?? 'N/D'}`,
      `Efectivo: ${this.money(close.cash)}`,
      `Transferencias: ${this.money(close.transfer)}`,
      `Tarjeta: ${this.money(close.card)}`,
      `Gastos: ${this.money(close.expenses)}`,
      `Total neto: ${this.money(close.netTotal)}`,
      `Efectivo entregado: ${this.money(close.cashDelivered)}`,
      `Diferencia: ${this.money(close.difference)}`,
      'Estado: pending',
      `PDF: ${pdfUrl}`,
    ].join('\n');
  }

  private async enqueueCloseNotifications(
    closeId: string,
    pdfBytes: Uint8Array,
    fileName: string,
    pdfUrl: string,
  ) {
    const close = await this.findCloseOrThrow(closeId);
    const recipients = await this.prisma.user.findMany({
      where: { role: { in: ['ADMIN', 'ASISTENTE'] }, blocked: false },
      select: { id: true, telefono: true },
    });
    const message = this.buildCloseAdminMessage(close, pdfUrl);
    let sent = 0;
    const errors: string[] = [];
    for (const recipient of recipients) {
      try {
        await this.notifications.enqueueWhatsAppDocument({
          recipientUserId: recipient.id,
          toNumber: recipient.telefono,
          messageText: message,
          fileName,
          bytes: pdfBytes,
          mimeType: 'application/pdf',
          dedupeKey: `daily-close:${close.id}:${recipient.id}`,
          payload: { kind: 'daily_close', closeId: close.id, pdfUrl },
          allowOutsideBusinessHours: true,
        });
        sent += 1;
      } catch (error) {
        errors.push(error instanceof Error ? error.message : String(error));
      }
    }

    await this.prisma.close.update({
      where: { id: close.id },
      data: {
        notificationStatus: sent > 0 ? 'sent' : 'failed',
        notificationError: errors.length ? errors.join(' | ') : null,
      },
    });
  }

  async generateAiReport(id: string, actor: Actor) {
    this.ensureReviewer(actor);
    const close = await this.findCloseOrThrow(id);
    const previous = await this.prisma.close.findMany({
      where: {
        type: close.type,
        id: { not: close.id },
        date: { lt: close.date },
      },
      orderBy: { date: 'desc' },
      take: 10,
      include: { transfers: { include: { vouchers: true } } },
    });

    const appConfig = await this.prisma.appConfig.findUnique({
      where: { id: 'global' },
      select: { openAiApiKey: true, openAiModel: true },
    });
    const apiKey =
      (
        this.config.get<string>('OPENAI_API_KEY') ??
        process.env.OPENAI_API_KEY ??
        ''
      ).trim() || (appConfig?.openAiApiKey ?? '').trim();
    const model =
      (
        this.config.get<string>('OPENAI_MODEL') ??
        process.env.OPENAI_MODEL ??
        ''
      ).trim() ||
      (appConfig?.openAiModel ?? '').trim() ||
      'gpt-4o-mini';

    const evidenceUrls = close.transfers.flatMap((transfer) =>
      transfer.vouchers.map((voucher) => voucher.fileUrl),
    );
    const context = {
      close,
      previousClosings: previous.map((item) => ({
        id: item.id,
        date: item.date,
        totalIncome: item.totalIncome,
        netTotal: item.netTotal,
        transfer: item.transfer,
        expenses: item.expenses,
        difference: item.difference,
      })),
    };

    let report: Record<string, unknown>;
    if (!apiKey) {
      report = {
        riskLevel: 'medium',
        summary:
          'No hay API key de OpenAI configurada. Se guardo una revision basica del sistema.',
        detectedIssues:
          evidenceUrls.length === 0 ? ['No hay vouchers visibles.'] : [],
        suggestedAdminActions: [
          'Configurar OpenAI para analisis completo con imagenes.',
          'Revisar vouchers manualmente.',
        ],
        confidenceLevel: 'low',
        evidenceReviewed: evidenceUrls,
      };
    } else {
      const content: Array<Record<string, unknown>> = [
        {
          type: 'text',
          text:
            'Analiza este cierre diario contable. Devuelve SOLO JSON con riskLevel(low|medium|high), summary, detectedIssues[], suggestedAdminActions[], confidenceLevel y evidenceReviewed[]. ' +
            JSON.stringify(context),
        },
        ...evidenceUrls
          .filter((url) => /^https?:\/\//i.test(url))
          .slice(0, 8)
          .map((url) => ({ type: 'image_url', image_url: { url } })),
      ];
      const res = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
          authorization: `Bearer ${apiKey}`,
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          model,
          temperature: 0.1,
          response_format: { type: 'json_object' },
          messages: [
            {
              role: 'system',
              content:
                'Eres auditor contable. No apruebas ni rechazas; solo alertas riesgos.',
            },
            { role: 'user', content },
          ],
        }),
      });
      if (!res.ok) {
        throw new BadRequestException(
          `No se pudo generar Informe IA: HTTP ${res.status}`,
        );
      }
      const json = (await res.json()) as any;
      const raw = json?.choices?.[0]?.message?.content;
      report = raw ? JSON.parse(raw) : {};
    }

    const riskLevel = String(
      report.riskLevel ?? report.ai_risk_level ?? 'medium',
    ).toLowerCase();
    const summary = String(
      report.summary ?? report.ai_report_summary ?? 'Informe IA generado.',
    );
    return this.prisma.close.update({
      where: { id: close.id },
      data: {
        aiRiskLevel: ['low', 'medium', 'high'].includes(riskLevel)
          ? riskLevel
          : 'medium',
        aiReportSummary: summary,
        aiReportJson: report as Prisma.InputJsonValue,
        aiGeneratedAt: new Date(),
      },
      include: { transfers: { include: { vouchers: true } } },
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
        bankAccount: this.toNullableTrimmed(dto.bankAccount),
        collaboratorName: this.toNullableTrimmed(dto.collaboratorName),
        note: this.toNullableTrimmed(dto.note),
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

  async getDepositOrderById(id: string) {
    const row = await this.prisma.depositOrder.findUnique({ where: { id } });
    if (!row) throw new NotFoundException('Depósito bancario no encontrado');
    return row;
  }

  async updateDepositOrder(
    id: string,
    dto: UpdateDepositOrderDto,
    actor: Actor,
  ) {
    this.ensureAdmin(actor);

    const existing = await this.prisma.depositOrder.findUnique({
      where: { id },
    });
    if (!existing)
      throw new NotFoundException('Depósito bancario no encontrado');

    const status =
      dto.status != null
        ? (dto.status as unknown as DepositOrderStatus)
        : undefined;
    const markingExecuted =
      status === DepositOrderStatusDto.EXECUTED || dto.voucherUrl != null;

    const executor = markingExecuted
      ? await this.prisma.user.findUnique({
          where: { id: actor.id! },
          select: { nombreCompleto: true },
        })
      : null;

    return this.prisma.depositOrder.update({
      where: { id },
      data: {
        ...(dto.windowFrom != null
          ? { windowFrom: new Date(dto.windowFrom) }
          : {}),
        ...(dto.windowTo != null ? { windowTo: new Date(dto.windowTo) } : {}),
        ...(dto.bankName != null ? { bankName: dto.bankName.trim() } : {}),
        ...(dto.bankAccount != null
          ? { bankAccount: this.toNullableTrimmed(dto.bankAccount) }
          : {}),
        ...(dto.collaboratorName != null
          ? { collaboratorName: this.toNullableTrimmed(dto.collaboratorName) }
          : {}),
        ...(dto.note != null ? { note: this.toNullableTrimmed(dto.note) } : {}),
        ...(dto.reserveAmount != null
          ? { reserveAmount: dto.reserveAmount }
          : {}),
        ...(dto.totalAvailableCash != null
          ? { totalAvailableCash: dto.totalAvailableCash }
          : {}),
        ...(dto.depositTotal != null ? { depositTotal: dto.depositTotal } : {}),
        ...(dto.closesCountByType != null
          ? { closesCountByType: dto.closesCountByType }
          : {}),
        ...(dto.depositByType != null
          ? { depositByType: dto.depositByType }
          : {}),
        ...(dto.accountByType != null
          ? { accountByType: dto.accountByType }
          : {}),
        ...(status != null ? { status } : {}),
        ...(dto.voucherUrl != null
          ? { voucherUrl: this.toNullableTrimmed(dto.voucherUrl) }
          : {}),
        ...(dto.voucherFileName != null
          ? { voucherFileName: this.toNullableTrimmed(dto.voucherFileName) }
          : {}),
        ...(dto.voucherMimeType != null
          ? { voucherMimeType: this.toNullableTrimmed(dto.voucherMimeType) }
          : {}),
        ...(markingExecuted
          ? {
              status: DepositOrderStatus.EXECUTED,
              executedAt: new Date(),
              executedById: actor.id!,
              executedByName: executor?.nombreCompleto ?? null,
            }
          : {}),
      },
    });
  }

  async attachDepositOrderVoucher(
    id: string,
    params: {
      voucherUrl: string;
      voucherFileName: string;
      voucherMimeType: string;
    },
    actor: Actor,
  ) {
    this.ensureAdmin(actor);

    const existing = await this.prisma.depositOrder.findUnique({
      where: { id },
    });
    if (!existing)
      throw new NotFoundException('Depósito bancario no encontrado');
    if (existing.status === DepositOrderStatus.CANCELLED) {
      throw new BadRequestException(
        'No se puede adjuntar voucher a un depósito cancelado',
      );
    }

    const executor = await this.prisma.user.findUnique({
      where: { id: actor.id! },
      select: { nombreCompleto: true },
    });

    return this.prisma.depositOrder.update({
      where: { id },
      data: {
        voucherUrl: params.voucherUrl.trim(),
        voucherFileName: params.voucherFileName.trim(),
        voucherMimeType: params.voucherMimeType.trim(),
        status: DepositOrderStatus.EXECUTED,
        executedAt: new Date(),
        executedById: actor.id!,
        executedByName: executor?.nombreCompleto ?? null,
      },
    });
  }

  async deleteDepositOrder(id: string, actor: Actor) {
    this.ensureAdmin(actor);

    const existing = await this.prisma.depositOrder.findUnique({
      where: { id },
    });
    if (!existing)
      throw new NotFoundException('Depósito bancario no encontrado');

    return this.prisma.depositOrder.delete({ where: { id } });
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

  async updateFiscalInvoice(
    id: string,
    dto: UpdateFiscalInvoiceDto,
    actor: Actor,
  ) {
    this.normalizeRoleGuard(actor);

    const existing = await this.prisma.fiscalInvoice.findUnique({
      where: { id },
    });
    if (!existing) throw new NotFoundException('Factura fiscal no encontrada');

    return this.prisma.fiscalInvoice.update({
      where: { id },
      data: {
        ...(dto.kind != null ? { kind: dto.kind } : {}),
        ...(dto.invoiceDate != null
          ? { invoiceDate: new Date(dto.invoiceDate) }
          : {}),
        ...(dto.imageUrl != null ? { imageUrl: dto.imageUrl.trim() } : {}),
        ...(dto.note != null ? { note: dto.note.trim() || null } : {}),
      },
    });
  }

  async deleteFiscalInvoice(id: string, actor: Actor) {
    this.normalizeRoleGuard(actor);

    const existing = await this.prisma.fiscalInvoice.findUnique({
      where: { id },
    });
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
      orderBy: [
        { active: 'desc' },
        { nextDueDate: 'asc' },
        { createdAt: 'desc' },
      ],
    });
  }

  async updatePayableService(
    id: string,
    dto: UpdatePayableServiceDto,
    actor: Actor,
  ) {
    this.normalizeRoleGuard(actor);

    const existing = await this.prisma.payableService.findUnique({
      where: { id },
    });
    if (!existing) {
      throw new NotFoundException('Servicio por pagar no encontrado');
    }

    return this.prisma.payableService.update({
      where: { id },
      data: {
        ...(dto.title != null ? { title: dto.title.trim() } : {}),
        ...(dto.providerKind != null ? { providerKind: dto.providerKind } : {}),
        ...(dto.providerName != null
          ? { providerName: dto.providerName.trim() }
          : {}),
        ...(dto.description != null
          ? { description: this.toNullableTrimmed(dto.description) }
          : {}),
        ...(dto.frequency != null ? { frequency: dto.frequency } : {}),
        ...(dto.defaultAmount != null
          ? { defaultAmount: dto.defaultAmount }
          : {}),
        ...(dto.nextDueDate != null
          ? { nextDueDate: new Date(dto.nextDueDate) }
          : {}),
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

    if (dto.amount <= 0) {
      throw new BadRequestException('El monto debe ser mayor a 0');
    }

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
          active:
            service.frequency === PayableFrequency.ONE_TIME ? false : true,
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
