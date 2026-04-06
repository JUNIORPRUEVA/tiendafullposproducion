import { BadRequestException, ForbiddenException, Injectable, Logger, NotFoundException } from '@nestjs/common';
import {
  OrderDocumentFlowStatus,
  Prisma,
  Role,
  ServiceOrderStatus,
  type ServiceOrderCategory,
  type ServiceOrderType,
} from '@prisma/client';
import PDFDocument from 'pdfkit';
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { PrismaService } from '../prisma/prisma.service';
import {
  SERVICE_ORDER_CATEGORY_FROM_DB,
  SERVICE_ORDER_TYPE_FROM_DB,
} from '../service-orders/service-orders.constants';
import { EditOrderDocumentFlowDraftDto } from './dto/edit-order-document-flow-draft.dto';

type AuthUser = { id: string; role: Role };

type DocumentFlowRow = Prisma.OrderDocumentFlowGetPayload<{
  include: {
    order: {
      include: {
        client: true;
        quotation: {
          include: {
            items: {
              orderBy: { createdAt: 'asc' };
            };
          };
        };
      };
    };
    preparedBy: { select: { id: true; nombreCompleto: true; email: true } };
    approvedBy: { select: { id: true; nombreCompleto: true; email: true } };
  };
}>;

type ServiceOrderContext = Prisma.ServiceOrderGetPayload<{
  include: {
    client: true;
    quotation: {
      include: {
        items: {
          orderBy: { createdAt: 'asc' };
        };
      };
    };
  };
}>;

type InvoiceDraftItem = {
  description: string;
  qty: number;
  unitPrice: number;
  lineTotal: number;
};

type InvoiceDraft = {
  version: number;
  currency: string;
  orderId: string;
  clientName: string;
  clientPhone: string;
  items: InvoiceDraftItem[];
  subtotal: number;
  tax: number;
  total: number;
  notes: string;
};

type WarrantyDraft = {
  version: number;
  orderId: string;
  clientName: string;
  serviceType: string;
  category: string;
  title: string;
  summary: string;
  terms: string[];
};

@Injectable()
export class OrderDocumentFlowService {
  private readonly logger = new Logger(OrderDocumentFlowService.name);

  constructor(private readonly prisma: PrismaService) {}

  private readonly include = {
    order: {
      include: {
        client: true,
        quotation: {
          include: {
            items: {
              orderBy: { createdAt: 'asc' as const },
            },
          },
        },
      },
    },
    preparedBy: { select: { id: true, nombreCompleto: true, email: true } },
    approvedBy: { select: { id: true, nombreCompleto: true, email: true } },
  } as const;

  async list(user: AuthUser, rawStatus?: string) {
    this.assertAssistantOrAdmin(user);
    const where: Prisma.OrderDocumentFlowWhereInput = rawStatus
      ? { status: this.statusFromApi(rawStatus) }
      : {};

    const items = await this.prisma.orderDocumentFlow.findMany({
      where,
      include: this.include,
      orderBy: [{ sentAt: 'desc' }, { updatedAt: 'desc' }, { createdAt: 'desc' }],
    });

    return items.map((item) => this.mapFlow(item));
  }

  async findByOrderId(user: AuthUser, orderId: string) {
    this.assertAssistantOrAdmin(user);
    const item = await this.prisma.orderDocumentFlow.findUnique({
      where: { orderId },
      include: this.include,
    });
    if (!item) {
      throw new NotFoundException('Flujo documental no encontrado para esta orden');
    }
    return this.mapFlow(item);
  }

  async editDraft(user: AuthUser, id: string, dto: EditOrderDocumentFlowDraftDto) {
    this.assertAssistantOrAdmin(user);
    const current = await this.findFlowById(id);

    const invoiceDraft = dto.invoiceDraftJson == null
      ? this.normalizeInvoiceDraft(current.invoiceDraftJson, current.order)
      : this.normalizeInvoiceDraft(dto.invoiceDraftJson, current.order);
    const warrantyDraft = dto.warrantyDraftJson == null
      ? this.normalizeWarrantyDraft(current.warrantyDraftJson, current.order)
      : this.normalizeWarrantyDraft(dto.warrantyDraftJson, current.order);

    const nextStatus = current.order.status === ServiceOrderStatus.FINALIZADO
      ? OrderDocumentFlowStatus.READY_FOR_FINALIZATION
      : OrderDocumentFlowStatus.READY_FOR_REVIEW;

    const updated = await this.prisma.orderDocumentFlow.update({
      where: { id },
      include: this.include,
      data: {
        invoiceDraftJson: invoiceDraft as Prisma.InputJsonValue,
        warrantyDraftJson: warrantyDraft as Prisma.InputJsonValue,
        preparedById: user.id,
        status: current.status === OrderDocumentFlowStatus.SENT ? current.status : nextStatus,
      },
    });

    return this.mapFlow(updated);
  }

  async generate(user: AuthUser, id: string) {
    this.assertAssistantOrAdmin(user);
    const current = await this.findFlowById(id);
    const invoiceDraft = this.normalizeInvoiceDraft(current.invoiceDraftJson, current.order);
    const warrantyDraft = this.normalizeWarrantyDraft(current.warrantyDraftJson, current.order);

    const invoiceFinalUrl = await this.writeInvoicePdf(current, invoiceDraft);
    const warrantyFinalUrl = await this.writeWarrantyPdf(current, warrantyDraft);

    const updated = await this.prisma.orderDocumentFlow.update({
      where: { id },
      include: this.include,
      data: {
        invoiceDraftJson: invoiceDraft as Prisma.InputJsonValue,
        warrantyDraftJson: warrantyDraft as Prisma.InputJsonValue,
        invoiceFinalUrl,
        warrantyFinalUrl,
        approvedById: user.id,
        status: OrderDocumentFlowStatus.APPROVED,
      },
    });

    return this.mapFlow(updated);
  }

  async send(user: AuthUser, id: string) {
    this.assertAssistantOrAdmin(user);
    let flow = await this.findFlowById(id);

    if (!flow.invoiceFinalUrl || !flow.warrantyFinalUrl) {
      await this.generate(user, id);
      flow = await this.findFlowById(id);
    }

    const updated = await this.prisma.orderDocumentFlow.update({
      where: { id },
      include: this.include,
      data: {
        status: OrderDocumentFlowStatus.SENT,
        sentAt: new Date(),
      },
    });

    const mapped = this.mapFlow(updated);
    return {
      flow: mapped,
      whatsappPayload: {
        toNumber: updated.order.client.telefono,
        messageText: [
          `Hola ${updated.order.client.nombre},`,
          'Adjuntamos la factura y la garantía de su servicio.',
          `Orden: ${updated.order.id}`,
          `Factura: ${mapped.invoiceFinalUrl ?? 'No disponible'}`,
          `Garantía: ${mapped.warrantyFinalUrl ?? 'No disponible'}`,
        ].join('\n'),
        attachments: [mapped.invoiceFinalUrl, mapped.warrantyFinalUrl].filter(
          (value): value is string => typeof value === 'string' && value.length > 0,
        ),
      },
    };
  }

  async syncFromServiceOrderStatus(orderId: string, status: ServiceOrderStatus) {
    if (status === ServiceOrderStatus.EN_PROCESO) {
      await this.ensureFlowCreatedForOrder(orderId);
      return;
    }

    if (status !== ServiceOrderStatus.FINALIZADO) {
      return;
    }

    const current = await this.ensureFlowCreatedForOrder(orderId);
    if (current.status === OrderDocumentFlowStatus.APPROVED || current.status === OrderDocumentFlowStatus.SENT) {
      return;
    }

    await this.prisma.orderDocumentFlow.update({
      where: { id: current.id },
      data: {
        status: OrderDocumentFlowStatus.READY_FOR_FINALIZATION,
      },
    });
  }

  async ensureFlowCreatedForOrder(orderId: string) {
    const existing = await this.prisma.orderDocumentFlow.findUnique({
      where: { orderId },
      include: this.include,
    });
    if (existing) {
      return existing;
    }

    const order = await this.loadOrderContext(orderId);
    const created = await this.prisma.orderDocumentFlow.create({
      include: this.include,
      data: {
        orderId: order.id,
        status: OrderDocumentFlowStatus.PENDING_PREPARATION,
        invoiceDraftJson: this.buildDefaultInvoiceDraft(order) as Prisma.InputJsonValue,
        warrantyDraftJson: this.buildDefaultWarrantyDraft(order) as Prisma.InputJsonValue,
      },
    });

    return created;
  }

  private async findFlowById(id: string) {
    const flow = await this.prisma.orderDocumentFlow.findUnique({
      where: { id },
      include: this.include,
    });
    if (!flow) {
      throw new NotFoundException('Flujo documental no encontrado');
    }
    return flow;
  }

  private async loadOrderContext(orderId: string): Promise<ServiceOrderContext> {
    const order = await this.prisma.serviceOrder.findUnique({
      where: { id: orderId },
      include: {
        client: true,
        quotation: {
          include: {
            items: {
              orderBy: { createdAt: 'asc' },
            },
          },
        },
      },
    });
    if (!order) {
      throw new NotFoundException('Orden de servicio no encontrada');
    }
    return order;
  }

  private assertAssistantOrAdmin(user: AuthUser) {
    if (user.role === Role.ADMIN || user.role === Role.ASISTENTE) {
      return;
    }
    throw new ForbiddenException('No tienes acceso al flujo documental');
  }

  private statusFromApi(value: string) {
    switch ((value ?? '').trim()) {
      case 'pending_preparation':
        return OrderDocumentFlowStatus.PENDING_PREPARATION;
      case 'ready_for_review':
        return OrderDocumentFlowStatus.READY_FOR_REVIEW;
      case 'ready_for_finalization':
        return OrderDocumentFlowStatus.READY_FOR_FINALIZATION;
      case 'approved':
        return OrderDocumentFlowStatus.APPROVED;
      case 'rejected':
        return OrderDocumentFlowStatus.REJECTED;
      case 'sent':
        return OrderDocumentFlowStatus.SENT;
      default:
        throw new BadRequestException('Estado de flujo documental inválido');
    }
  }

  private statusToApi(value: OrderDocumentFlowStatus) {
    switch (value) {
      case OrderDocumentFlowStatus.PENDING_PREPARATION:
        return 'pending_preparation';
      case OrderDocumentFlowStatus.READY_FOR_REVIEW:
        return 'ready_for_review';
      case OrderDocumentFlowStatus.READY_FOR_FINALIZATION:
        return 'ready_for_finalization';
      case OrderDocumentFlowStatus.APPROVED:
        return 'approved';
      case OrderDocumentFlowStatus.REJECTED:
        return 'rejected';
      case OrderDocumentFlowStatus.SENT:
        return 'sent';
    }
  }

  private mapFlow(flow: DocumentFlowRow) {
    return {
      id: flow.id,
      orderId: flow.orderId,
      status: this.statusToApi(flow.status),
      invoiceDraftJson: flow.invoiceDraftJson,
      warrantyDraftJson: flow.warrantyDraftJson,
      invoiceFinalUrl: flow.invoiceFinalUrl,
      warrantyFinalUrl: flow.warrantyFinalUrl,
      preparedById: flow.preparedById,
      approvedById: flow.approvedById,
      sentAt: flow.sentAt,
      createdAt: flow.createdAt,
      updatedAt: flow.updatedAt,
      preparedBy: flow.preparedBy,
      approvedBy: flow.approvedBy,
      order: {
        id: flow.order.id,
        status: flow.order.status,
        serviceType: this.enumLabel(flow.order.serviceType),
        category: this.enumLabel(flow.order.category),
        scheduledFor: flow.order.scheduledFor,
        finalizedAt: flow.order.finalizedAt,
        createdAt: flow.order.createdAt,
        updatedAt: flow.order.updatedAt,
        client: {
          id: flow.order.client.id,
          nombre: flow.order.client.nombre,
          telefono: flow.order.client.telefono,
          direccion: flow.order.client.direccion,
        },
      },
    };
  }

  private buildDefaultInvoiceDraft(order: ServiceOrderContext): InvoiceDraft {
    const items: InvoiceDraftItem[] = order.quotation.items.map((item) => ({
      description: item.productNameSnapshot,
      qty: Number(item.qty),
      unitPrice: Number(item.unitPrice),
      lineTotal: Number(item.lineTotal),
    }));

    return {
      version: 1,
      currency: 'DOP',
      orderId: order.id,
      clientName: order.client.nombre,
      clientPhone: order.client.telefono,
      items,
      subtotal: Number(order.quotation.subtotal),
      tax: Number(order.quotation.itbisAmount),
      total: Number(order.quotation.total),
      notes: [order.technicalNote, order.extraRequirements]
        .map((item) => (item ?? '').trim())
        .filter((item) => item.length > 0)
        .join(' | '),
    };
  }

  private buildDefaultWarrantyDraft(order: ServiceOrderContext): WarrantyDraft {
    const serviceType = this.enumLabel(order.serviceType);
    const category = this.enumLabel(order.category);

    return {
      version: 1,
      orderId: order.id,
      clientName: order.client.nombre,
      serviceType,
      category,
      title: `Garantía servicio ${order.id.slice(0, 8).toUpperCase()}`,
      summary: `Cobertura inicial para ${serviceType} en categoría ${category}.`,
      terms: [
        'Cobertura sujeta a inspección técnica final.',
        'No cubre daños por manipulación externa o uso indebido.',
        'Conservar factura y este documento para futuras reclamaciones.',
      ],
    };
  }

  private normalizeInvoiceDraft(raw: Prisma.JsonValue | Record<string, unknown> | null, order: ServiceOrderContext): InvoiceDraft {
    const fallback = this.buildDefaultInvoiceDraft(order);
    const input = this.asObject(raw);
    const itemsRaw = Array.isArray(input?.items) ? input.items : [];
    const items = itemsRaw
      .map((item) => this.asObject(item))
      .filter((item): item is Record<string, unknown> => item != null)
      .map((item) => {
        const qty = this.toNumber(item.qty, 1);
        const unitPrice = this.toNumber(item.unitPrice, 0);
        const lineTotal = this.toNumber(item.lineTotal, qty * unitPrice);
        return {
          description: this.toText(item.description),
          qty,
          unitPrice,
          lineTotal,
        };
      })
      .filter((item) => item.description.length > 0);

    const subtotal = items.reduce((sum, item) => sum + item.lineTotal, 0);
    const tax = this.toNumber(input?.tax, fallback.tax);
    const total = this.toNumber(input?.total, subtotal + tax);
    const hasItems = items.length > 0;

    return {
      version: 1,
      currency: this.toText(input?.currency, fallback.currency),
      orderId: order.id,
      clientName: this.toText(input?.clientName, order.client.nombre),
      clientPhone: this.toText(input?.clientPhone, order.client.telefono),
      items: hasItems ? items : fallback.items,
      subtotal: hasItems ? subtotal : fallback.subtotal,
      tax,
      total: hasItems ? total : fallback.total,
      notes: this.toText(input?.notes, fallback.notes),
    };
  }

  private normalizeWarrantyDraft(raw: Prisma.JsonValue | Record<string, unknown> | null, order: ServiceOrderContext): WarrantyDraft {
    const fallback = this.buildDefaultWarrantyDraft(order);
    const input = this.asObject(raw);
    const terms = Array.isArray(input?.terms)
      ? input.terms
          .map((item) => this.toText(item))
          .filter((item) => item.length > 0)
      : fallback.terms;

    return {
      version: 1,
      orderId: order.id,
      clientName: this.toText(input?.clientName, order.client.nombre),
      serviceType: this.toText(input?.serviceType, fallback.serviceType),
      category: this.toText(input?.category, fallback.category),
      title: this.toText(input?.title, fallback.title),
      summary: this.toText(input?.summary, fallback.summary),
      terms: terms.length > 0 ? terms : fallback.terms,
    };
  }

  private async writeInvoicePdf(flow: DocumentFlowRow, draft: InvoiceDraft) {
    const fileName = 'invoice-final.pdf';
    const relativePath = join('document-flows', flow.id, fileName).replace(/\\/g, '/');
    const absolutePath = this.buildAbsoluteUploadPath(relativePath);

    const doc = new PDFDocument({ margin: 40, size: 'A4' });
    const chunks: Buffer[] = [];
    const pdfBuffer = new Promise<Buffer>((resolve, reject) => {
      doc.on('data', (chunk) => chunks.push(Buffer.from(chunk)));
      doc.on('end', () => resolve(Buffer.concat(chunks)));
      doc.on('error', reject);
    });
    doc.fontSize(18).text('Factura de servicio');
    doc.moveDown(0.5);
    doc.fontSize(11).text(`Orden: ${draft.orderId}`);
    doc.text(`Cliente: ${draft.clientName}`);
    doc.text(`Teléfono: ${draft.clientPhone}`);
    doc.text(`Moneda: ${draft.currency}`);
    doc.moveDown(0.8);
    doc.fontSize(12).text('Detalle');
    doc.moveDown(0.4);
    for (const item of draft.items) {
      doc.fontSize(10).text(
        `${item.description} | Cant: ${item.qty.toFixed(2)} | Unit: ${item.unitPrice.toFixed(2)} | Total: ${item.lineTotal.toFixed(2)}`,
      );
    }
    doc.moveDown(0.8);
    doc.fontSize(11).text(`Subtotal: ${draft.subtotal.toFixed(2)}`);
    doc.text(`Impuesto: ${draft.tax.toFixed(2)}`);
    doc.text(`Total: ${draft.total.toFixed(2)}`);
    if (draft.notes.trim().length > 0) {
      doc.moveDown(0.8);
      doc.text(`Notas: ${draft.notes}`);
    }
    doc.end();
    writeFileSync(absolutePath, await pdfBuffer);
    return `/${join('uploads', relativePath).replace(/\\/g, '/')}`;
  }

  private async writeWarrantyPdf(flow: DocumentFlowRow, draft: WarrantyDraft) {
    const fileName = 'warranty-final.pdf';
    const relativePath = join('document-flows', flow.id, fileName).replace(/\\/g, '/');
    const absolutePath = this.buildAbsoluteUploadPath(relativePath);

    const doc = new PDFDocument({ margin: 40, size: 'A4' });
    const chunks: Buffer[] = [];
    const pdfBuffer = new Promise<Buffer>((resolve, reject) => {
      doc.on('data', (chunk) => chunks.push(Buffer.from(chunk)));
      doc.on('end', () => resolve(Buffer.concat(chunks)));
      doc.on('error', reject);
    });
    doc.fontSize(18).text('Garantía de servicio');
    doc.moveDown(0.5);
    doc.fontSize(11).text(`Orden: ${draft.orderId}`);
    doc.text(`Cliente: ${draft.clientName}`);
    doc.text(`Servicio: ${draft.serviceType}`);
    doc.text(`Categoría: ${draft.category}`);
    doc.moveDown(0.8);
    doc.fontSize(12).text(draft.title);
    doc.moveDown(0.4);
    doc.fontSize(10).text(draft.summary);
    doc.moveDown(0.8);
    doc.fontSize(11).text('Términos');
    for (const term of draft.terms) {
      doc.fontSize(10).text(`- ${term}`);
    }
    doc.end();
    writeFileSync(absolutePath, await pdfBuffer);
    return `/${join('uploads', relativePath).replace(/\\/g, '/')}`;
  }

  private buildAbsoluteUploadPath(relativePath: string) {
    const uploadDirEnv = (process.env.UPLOAD_DIR ?? '').trim();
    const volumeDir = '/uploads';
    const volumeExists = existsSync(volumeDir);
    const uploadDir = uploadDirEnv.length > 0
      ? ((uploadDirEnv === './uploads' || uploadDirEnv === 'uploads') && volumeExists
          ? volumeDir
          : uploadDirEnv)
      : (volumeExists ? volumeDir : join(process.cwd(), 'uploads'));
    mkdirSync(dirname(join(uploadDir, relativePath)), { recursive: true });
    return join(uploadDir, relativePath);
  }

  private asObject(value: unknown) {
    if (value && typeof value === 'object' && !Array.isArray(value)) {
      return value as Record<string, unknown>;
    }
    return null;
  }

  private toText(value: unknown, fallback = '') {
    const normalized = `${value ?? fallback}`.trim();
    return normalized || fallback;
  }

  private toNumber(value: unknown, fallback = 0) {
    const numeric = Number(value);
    return Number.isFinite(numeric) ? numeric : fallback;
  }

  private enumLabel(value: ServiceOrderType | ServiceOrderCategory) {
    if (value in SERVICE_ORDER_TYPE_FROM_DB) {
      return SERVICE_ORDER_TYPE_FROM_DB[value as ServiceOrderType];
    }
    return SERVICE_ORDER_CATEGORY_FROM_DB[value as ServiceOrderCategory];
  }
}