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

type CompanyDocumentContext = {
  companyName: string;
  rnc: string;
  phone: string;
  address: string;
  logoBase64: string;
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
    const invoiceDraft = this.syncInvoiceDraftWithQuotation(
      this.normalizeInvoiceDraft(current.invoiceDraftJson, current.order),
      current.order,
    );
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
        quotationId: flow.order.quotation?.id ?? null,
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
      title: 'CARTA DE GARANTIA',
      summary: `Garantia correspondiente al servicio de ${serviceType} en la categoria ${category}.`,
      terms: [
        'Cobertura sujeta a inspección técnica final.',
        'No cubre daños por manipulación externa o uso indebido.',
        'Conservar factura y este documento para futuras reclamaciones.',
      ],
    };
  }

  private syncInvoiceDraftWithQuotation(draft: InvoiceDraft, order: ServiceOrderContext): InvoiceDraft {
    const quotationItems = order.quotation.items.map((item) => ({
      description: this.toText(item.productNameSnapshot),
      qty: Number(item.qty),
      unitPrice: Number(item.unitPrice),
      lineTotal: Number(item.lineTotal),
    })).filter((item) => item.description.length > 0);

    if (quotationItems.length === 0) {
      return draft;
    }

    return {
      ...draft,
      clientName: this.toText(order.client.nombre, draft.clientName),
      clientPhone: this.toText(order.client.telefono, draft.clientPhone),
      items: quotationItems,
      subtotal: Number(order.quotation.subtotal),
      tax: Number(order.quotation.itbisAmount),
      total: Number(order.quotation.total),
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
    const company = await this.getCompanyDocumentContext();
    const issueDate = flow.order.finalizedAt ?? flow.order.updatedAt ?? flow.order.createdAt ?? new Date();
    const invoiceNumber = `FACT-${flow.order.id.replace(/-/g, '').slice(0, 8).toUpperCase()}`;
    const contentWidth = 515;
    const leftColumnWidth = 250;
    const rightColumnWidth = contentWidth - leftColumnWidth;

    const doc = new PDFDocument({ margin: 40, size: 'A4' });
    const chunks: Buffer[] = [];
    const pdfBuffer = new Promise<Buffer>((resolve, reject) => {
      doc.on('data', (chunk) => chunks.push(Buffer.from(chunk)));
      doc.on('end', () => resolve(Buffer.concat(chunks)));
      doc.on('error', reject);
    });

    const logoBuffer = this.decodeLogoBase64(company.logoBase64);
    const headerTop = doc.y;
    if (logoBuffer) {
      try {
        doc.image(logoBuffer, doc.page.margins.left, headerTop, {
          fit: [58, 58],
          align: 'left',
          valign: 'top',
        });
      } catch (error) {
        this.logger.warn(`No se pudo insertar logo en factura PDF: ${error}`);
      }
    }

    const infoX = doc.page.margins.left + 72;
    doc.font('Helvetica-Bold').fontSize(16).text(company.companyName, infoX, headerTop, {
      width: leftColumnWidth - 72,
      align: 'left',
    });
    doc.font('Helvetica').fontSize(9);
    let companyInfoY = headerTop + 20;
    const companyLines = [
      company.rnc.length > 0 ? `RNC: ${company.rnc}` : '',
      company.phone.length > 0 ? `Tel: ${company.phone}` : '',
      company.address,
    ].filter((value) => value.trim().length > 0);
    for (const line of companyLines) {
      doc.text(line, infoX, companyInfoY, {
        width: leftColumnWidth - 72,
        align: 'left',
      });
      companyInfoY += 12;
    }

    const invoiceMetaX = doc.page.margins.left + leftColumnWidth + 15;
    doc.font('Helvetica-Bold').fontSize(15).text('Factura', invoiceMetaX, headerTop, {
      width: rightColumnWidth - 15,
      align: 'left',
    });
    doc.font('Helvetica').fontSize(10);
    const metaLines = [
      `No. factura: ${invoiceNumber}`,
      `Orden: ${draft.orderId}`,
      `Moneda: ${draft.currency}`,
    ];
    let metaY = headerTop + 22;
    for (const line of metaLines) {
      doc.text(line, invoiceMetaX, metaY, {
        width: rightColumnWidth - 15,
        align: 'left',
      });
      metaY += 13;
    }

    const dividerY = Math.max(companyInfoY, metaY) + 8;
    doc.moveTo(doc.page.margins.left, dividerY).lineTo(doc.page.width - doc.page.margins.right, dividerY).stroke('#D9DEE7');

    const clientBlockTop = dividerY + 14;
    doc.font('Helvetica-Bold').fontSize(11).text('Datos del cliente', doc.page.margins.left, clientBlockTop, {
      width: 250,
      align: 'left',
    });
    doc.font('Helvetica').fontSize(10);
    let clientY = clientBlockTop + 16;
    const clientLines = [
      `Cliente: ${draft.clientName}`,
      `Teléfono: ${draft.clientPhone}`,
      flow.order.client.direccion?.trim().length ? `Dirección: ${flow.order.client.direccion?.trim()}` : '',
    ].filter((value) => `${value}`.trim().length > 0);
    for (const line of clientLines) {
      doc.text(line, doc.page.margins.left, clientY, {
        width: 280,
        align: 'left',
      });
      clientY += 13;
    }

    const detailMetaX = doc.page.margins.left + 320;
    doc.font('Helvetica-Bold').fontSize(11).text('Datos de factura', detailMetaX, clientBlockTop, {
      width: 180,
      align: 'left',
    });
    doc.font('Helvetica').fontSize(10);
    doc.text(`Fecha: ${issueDate.toLocaleDateString('es-DO')}`, detailMetaX, clientBlockTop + 16, {
      width: 180,
      align: 'left',
    });
    doc.text(`Comprobante: ${invoiceNumber}`, detailMetaX, clientBlockTop + 29, {
      width: 180,
      align: 'left',
    });

    const tableTop = Math.max(clientY, clientBlockTop + 45) + 16;
    const tableX = doc.page.margins.left;
    const descWidth = 250;
    const qtyWidth = 70;
    const priceWidth = 90;
    const totalWidth = 105;

    doc.roundedRect(tableX, tableTop, contentWidth, 24, 6).fill('#EEF3FB');
    doc.fillColor('#1F2430').font('Helvetica-Bold').fontSize(10);
    doc.text('Detalle', tableX + 10, tableTop + 7, { width: descWidth - 20, align: 'left' });
    doc.text('Cant.', tableX + descWidth, tableTop + 7, { width: qtyWidth, align: 'center' });
    doc.text('Precio', tableX + descWidth + qtyWidth, tableTop + 7, { width: priceWidth - 10, align: 'right' });
    doc.text('Subtotal', tableX + descWidth + qtyWidth + priceWidth, tableTop + 7, { width: totalWidth - 10, align: 'right' });

    let rowY = tableTop + 30;
    doc.font('Helvetica').fontSize(10).fillColor('#111827');
    for (const item of draft.items) {
      const rowHeight = Math.max(22, doc.heightOfString(item.description, { width: descWidth - 20 }) + 8);
      doc.roundedRect(tableX, rowY - 4, contentWidth, rowHeight, 4).stroke('#E5EAF2');
      doc.text(item.description, tableX + 10, rowY, { width: descWidth - 20, align: 'left' });
      doc.text(item.qty.toFixed(2), tableX + descWidth, rowY, { width: qtyWidth, align: 'center' });
      doc.text(item.unitPrice.toFixed(2), tableX + descWidth + qtyWidth, rowY, { width: priceWidth - 10, align: 'right' });
      doc.text(item.lineTotal.toFixed(2), tableX + descWidth + qtyWidth + priceWidth, rowY, { width: totalWidth - 10, align: 'right' });
      rowY += rowHeight + 6;
    }

    const totalsX = tableX + 315;
    doc.font('Helvetica').fontSize(10);
    doc.text(`Subtotal: ${draft.subtotal.toFixed(2)}`, totalsX, rowY + 8, { width: 200, align: 'right' });
    doc.text(`Impuesto: ${draft.tax.toFixed(2)}`, totalsX, rowY + 22, { width: 200, align: 'right' });
    doc.font('Helvetica-Bold').fontSize(12).text(`Total: ${draft.total.toFixed(2)}`, totalsX, rowY + 38, { width: 200, align: 'right' });

    if (draft.notes.trim().length > 0) {
      doc.font('Helvetica-Bold').fontSize(11).text('Notas', tableX, rowY + 46, { width: 120, align: 'left' });
      doc.font('Helvetica').fontSize(10).text(draft.notes, tableX, rowY + 62, {
        width: 280,
        align: 'left',
      });
    }
    doc.end();
    writeFileSync(absolutePath, await pdfBuffer);
    return `/${join('uploads', relativePath).replace(/\\/g, '/')}`;
  }

  private async writeWarrantyPdf(flow: DocumentFlowRow, draft: WarrantyDraft) {
    const fileName = 'warranty-final.pdf';
    const relativePath = join('document-flows', flow.id, fileName).replace(/\\/g, '/');
    const absolutePath = this.buildAbsoluteUploadPath(relativePath);
    const company = await this.getCompanyDocumentContext();
    const title = this.toText(draft.title, 'CARTA DE GARANTIA');
    const summary = this.toText(draft.summary);
    const issueDate = flow.order.finalizedAt ?? flow.order.updatedAt ?? flow.order.createdAt ?? new Date();
    const terms = draft.terms
      .map((item) => this.toText(item))
      .filter((item) => item.length > 0);
    const detailLines = [
      ['Fecha', issueDate.toLocaleDateString('es-DO')],
      ['Orden', draft.orderId],
      ['Cliente', draft.clientName],
      ['Telefono', flow.order.client.telefono],
      ['Servicio', draft.serviceType],
      ['Categoria', draft.category],
    ].filter((entry): entry is [string, string] => entry[1].trim().length > 0);

    const doc = new PDFDocument({ margin: 40, size: 'A4' });
    const chunks: Buffer[] = [];
    const pdfBuffer = new Promise<Buffer>((resolve, reject) => {
      doc.on('data', (chunk) => chunks.push(Buffer.from(chunk)));
      doc.on('end', () => resolve(Buffer.concat(chunks)));
      doc.on('error', reject);
    });

    doc.font('Helvetica-Bold').fontSize(18).text(company.companyName, { align: 'center' });
    doc.font('Helvetica').fontSize(10);
    if (company.rnc.length > 0) {
      doc.text(`RNC: ${company.rnc}`, { align: 'center' });
    }
    if (company.phone.length > 0) {
      doc.text(`Tel: ${company.phone}`, { align: 'center' });
    }
    if (company.address.length > 0) {
      doc.text(company.address, { align: 'center' });
    }

    doc.moveDown(1);
    doc.font('Helvetica-Bold').fontSize(16).text(title, { align: 'center' });
    doc.moveDown(0.8);

    doc.font('Helvetica').fontSize(11);
    for (const [label, value] of detailLines) {
      doc.text(`${label}: ${value}`);
    }

    doc.moveDown(0.8);
    doc.text(
      [
        `Por medio de la presente, ${company.companyName} deja constancia de la garantia correspondiente al servicio realizado`,
        draft.clientName.trim().length > 0 ? ` para ${draft.clientName.trim()}` : '',
        draft.serviceType.trim().length > 0 ? `, relacionado con ${draft.serviceType.trim()}` : '',
        draft.category.trim().length > 0 ? ` en la categoria ${draft.category.trim()}` : '',
        '.',
      ].join(''),
      { align: 'justify' },
    );

    if (summary.length > 0) {
      doc.moveDown(0.8);
      doc.font('Helvetica-Bold').text('Cobertura');
      doc.font('Helvetica').text(summary, { align: 'justify' });
    }

    if (terms.length > 0) {
      doc.moveDown(0.8);
      doc.font('Helvetica-Bold').text('Condiciones de garantia');
      doc.font('Helvetica');
      for (const term of terms) {
        doc.text(`- ${term}`);
      }
    }

    doc.moveDown(0.8);
    doc.text(
      'Para cualquier reclamacion, conserve la factura y esta carta de garantia para futuras validaciones.',
      { align: 'justify' },
    );

    doc.moveDown(1.6);
    const signatureTop = doc.y;
    const contentWidth = doc.page.width - doc.page.margins.left - doc.page.margins.right;
    const gap = 24;
    const columnWidth = (contentWidth - gap) / 2;
    const leftX = doc.page.margins.left;
    const rightX = leftX + columnWidth + gap;

    doc.font('Helvetica-Bold').text('Cliente', leftX, signatureTop, { width: columnWidth, align: 'center' });
    doc.text('Empresa', rightX, signatureTop, { width: columnWidth, align: 'center' });
    doc.moveDown(0.5);
    doc.font('Helvetica').text(this.toText(draft.clientName, 'Cliente'), leftX, doc.y, { width: columnWidth, align: 'center' });
    doc.text(company.companyName, rightX, doc.y, { width: columnWidth, align: 'center' });

    doc.end();
    writeFileSync(absolutePath, await pdfBuffer);
    return `/${join('uploads', relativePath).replace(/\\/g, '/')}`;
  }

  private async getCompanyDocumentContext(): Promise<CompanyDocumentContext> {
    const appConfig = await this.prisma.appConfig.findUnique({
      where: { id: 'global' },
      select: {
        companyName: true,
        rnc: true,
        phone: true,
        address: true,
        logoBase64: true,
      },
    });

    return {
      companyName: this.toText(appConfig?.companyName, 'FULLTECH'),
      rnc: this.toText(appConfig?.rnc),
      phone: this.toText(appConfig?.phone),
      address: this.toText(appConfig?.address),
      logoBase64: this.toText(appConfig?.logoBase64),
    };
  }

  private decodeLogoBase64(raw: string) {
    const value = this.toText(raw);
    if (value.length === 0) return null;
    const normalized = value.includes(',') ? value.split(',').pop() ?? '' : value;
    try {
      return Buffer.from(normalized, 'base64');
    } catch {
      return null;
    }
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