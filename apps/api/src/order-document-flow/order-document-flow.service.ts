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
    const pageWidth = 515;
    const leftColumnWidth = 300;
    const rightColumnWidth = 185;
    const tableWidth = pageWidth;
    const descriptionWidth = 245;
    const qtyWidth = 70;
    const priceWidth = 90;
    const amountWidth = tableWidth - descriptionWidth - qtyWidth - priceWidth;
    const money = (value: number) => `RD$ ${value.toFixed(2)}`;
    const quantity = (value: number) => value % 1 === 0 ? value.toFixed(0) : value.toFixed(2);

    const doc = new PDFDocument({ margin: 40, size: 'A4' });
    const chunks: Buffer[] = [];
    const pdfBuffer = new Promise<Buffer>((resolve, reject) => {
      doc.on('data', (chunk) => chunks.push(Buffer.from(chunk)));
      doc.on('end', () => resolve(Buffer.concat(chunks)));
      doc.on('error', reject);
    });

    const logoBuffer = this.decodeLogoBase64(company.logoBase64);
    const drawTableHeader = (top: number) => {
      doc.save();
      doc.roundedRect(doc.page.margins.left, top, tableWidth, 24, 6).fill('#EAF1FF');
      doc.restore();
      doc.fillColor('#1F2430').font('Helvetica-Bold').fontSize(10);
      doc.text('Descripción', doc.page.margins.left + 10, top + 7, {
        width: descriptionWidth - 20,
        align: 'left',
      });
      doc.text('Cant.', doc.page.margins.left + descriptionWidth, top + 7, {
        width: qtyWidth,
        align: 'center',
      });
      doc.text('Precio', doc.page.margins.left + descriptionWidth + qtyWidth, top + 7, {
        width: priceWidth - 10,
        align: 'right',
      });
      doc.text('Importe', doc.page.margins.left + descriptionWidth + qtyWidth + priceWidth, top + 7, {
        width: amountWidth - 10,
        align: 'right',
      });
    };

    const drawHeader = () => {
      const top = doc.y;
      doc.save();
      doc.roundedRect(doc.page.margins.left, top, pageWidth, 94, 14).fill('#F8FAFC');
      doc.restore();

      if (logoBuffer) {
        try {
          doc.image(logoBuffer, doc.page.margins.left + 14, top + 16, {
            fit: [60, 60],
            align: 'left',
            valign: 'top',
          });
        } catch (error) {
          this.logger.warn(`No se pudo insertar logo en factura PDF: ${error}`);
        }
      }

      const companyInfoX = doc.page.margins.left + 88;
      doc.fillColor('#243145').font('Helvetica-Bold').fontSize(17).text(company.companyName, companyInfoX, top + 14, {
        width: leftColumnWidth - 74,
        align: 'left',
      });

      doc.font('Helvetica').fontSize(9).fillColor('#687385');
      const companyLines = [
        company.rnc.length > 0 ? `RNC: ${company.rnc}` : '',
        company.phone.length > 0 ? `Tel: ${company.phone}` : '',
        company.address,
      ].filter((value) => value.trim().length > 0);
      let companyLineY = top + 36;
      for (const line of companyLines) {
        doc.text(line, companyInfoX, companyLineY, {
          width: leftColumnWidth - 74,
          align: 'left',
        });
        companyLineY += 11;
      }

      const metaX = doc.page.margins.left + leftColumnWidth + 20;
      doc.save();
      doc.roundedRect(metaX, top + 12, rightColumnWidth, 68, 12).fill('#243145');
      doc.restore();
      doc.fillColor('#FFFFFF').font('Helvetica-Bold').fontSize(14).text('FACTURA', metaX + 12, top + 20, {
        width: rightColumnWidth - 24,
        align: 'left',
      });
      doc.font('Helvetica').fontSize(9.5);
      const metaLines = [
        `Factura No.: ${invoiceNumber}`,
        `Fecha: ${issueDate.toLocaleDateString('es-DO')}`,
        `Moneda: ${draft.currency}`,
      ];
      let metaLineY = top + 40;
      for (const line of metaLines) {
        doc.text(line, metaX + 12, metaLineY, {
          width: rightColumnWidth - 24,
          align: 'left',
        });
        metaLineY += 11;
      }

      doc.y = top + 108;
    };

    const drawCustomerBlock = () => {
      const top = doc.y;
      doc.save();
      doc.roundedRect(doc.page.margins.left, top, pageWidth, 72, 12).fill('#FFFFFF');
      doc.roundedRect(doc.page.margins.left, top, pageWidth, 72, 12).stroke('#E7ECF2');
      doc.restore();

      doc.fillColor('#243145').font('Helvetica-Bold').fontSize(11).text('Facturar a', doc.page.margins.left + 14, top + 12, {
        width: 220,
        align: 'left',
      });
      doc.font('Helvetica').fontSize(10).fillColor('#1F2430');
      const clientLines = [
        draft.clientName,
        `Tel: ${draft.clientPhone}`,
        flow.order.client.direccion?.trim() ?? '',
      ].filter((value) => value.trim().length > 0);
      let clientY = top + 28;
      for (const line of clientLines) {
        doc.text(line, doc.page.margins.left + 14, clientY, {
          width: 250,
          align: 'left',
        });
        clientY += 12;
      }

      doc.fillColor('#243145').font('Helvetica-Bold').fontSize(11).text('Referencia', doc.page.margins.left + 320, top + 12, {
        width: 180,
        align: 'left',
      });
      doc.font('Helvetica').fontSize(10).fillColor('#1F2430');
      doc.text(`Orden: ${draft.orderId}`, doc.page.margins.left + 320, top + 28, {
        width: 170,
        align: 'left',
      });
      doc.text(`Comprobante: ${invoiceNumber}`, doc.page.margins.left + 320, top + 40, {
        width: 170,
        align: 'left',
      });

      doc.y = top + 88;
    };

    drawHeader();
    drawCustomerBlock();
    drawTableHeader(doc.y);

    let rowY = doc.y + 32;
    let rowIndex = 0;
    for (const item of draft.items) {
      const rowHeight = Math.max(24, doc.heightOfString(item.description, { width: descriptionWidth - 20 }) + 10);
      const nextBottom = rowY + rowHeight + 6;
      if (nextBottom > doc.page.height - doc.page.margins.bottom - 130) {
        doc.addPage();
        drawHeader();
        drawCustomerBlock();
        drawTableHeader(doc.y);
        rowY = doc.y + 32;
      }

      doc.save();
      doc.roundedRect(doc.page.margins.left, rowY - 4, tableWidth, rowHeight, 6)
        .fill(rowIndex.isEven ? '#FFFFFF' : '#FAFBFD');
      doc.roundedRect(doc.page.margins.left, rowY - 4, tableWidth, rowHeight, 6)
        .stroke('#E7ECF2');
      doc.restore();

      doc.fillColor('#1F2430').font('Helvetica').fontSize(10);
      doc.text(item.description, doc.page.margins.left + 10, rowY + 3, {
        width: descriptionWidth - 20,
        align: 'left',
      });
      doc.text(quantity(item.qty), doc.page.margins.left + descriptionWidth, rowY + 3, {
        width: qtyWidth,
        align: 'center',
      });
      doc.text(money(item.unitPrice), doc.page.margins.left + descriptionWidth + qtyWidth, rowY + 3, {
        width: priceWidth - 10,
        align: 'right',
      });
      doc.font('Helvetica-Bold').text(money(item.lineTotal), doc.page.margins.left + descriptionWidth + qtyWidth + priceWidth, rowY + 3, {
        width: amountWidth - 10,
        align: 'right',
      });
      rowY += rowHeight + 6;
      rowIndex += 1;
    }

    const notesText = draft.notes.trim();
    const notesHeight = notesText.length > 0
      ? Math.max(54, doc.heightOfString(notesText, { width: 240 }) + 28)
      : 0;
    const totalsHeight = 88;
    if (rowY + Math.max(notesHeight, totalsHeight) > doc.page.height - doc.page.margins.bottom - 20) {
      doc.addPage();
      drawHeader();
      drawCustomerBlock();
      rowY = doc.y;
    }

    if (notesText.length > 0) {
      doc.save();
      doc.roundedRect(doc.page.margins.left, rowY + 6, 255, notesHeight, 12).fill('#FFFFFF');
      doc.roundedRect(doc.page.margins.left, rowY + 6, 255, notesHeight, 12).stroke('#E7ECF2');
      doc.restore();
      doc.fillColor('#243145').font('Helvetica-Bold').fontSize(11).text('Notas', doc.page.margins.left + 14, rowY + 18, {
        width: 220,
        align: 'left',
      });
      doc.fillColor('#1F2430').font('Helvetica').fontSize(10).text(notesText, doc.page.margins.left + 14, rowY + 34, {
        width: 227,
        align: 'left',
      });
    }

    const totalsX = doc.page.margins.left + 275;
    doc.save();
    doc.roundedRect(totalsX, rowY + 6, 240, totalsHeight, 12).fill('#F8FAFC');
    doc.roundedRect(totalsX, rowY + 6, 240, totalsHeight, 12).stroke('#D9E6FF');
    doc.restore();
    doc.fillColor('#243145').font('Helvetica-Bold').fontSize(11).text('Totales', totalsX + 14, rowY + 18, {
      width: 210,
      align: 'left',
    });
    doc.font('Helvetica').fontSize(10).fillColor('#1F2430');
    doc.text('Subtotal', totalsX + 14, rowY + 38, { width: 100, align: 'left' });
    doc.text(money(draft.subtotal), totalsX + 120, rowY + 38, { width: 100, align: 'right' });
    doc.text('Impuesto', totalsX + 14, rowY + 53, { width: 100, align: 'left' });
    doc.text(money(draft.tax), totalsX + 120, rowY + 53, { width: 100, align: 'right' });
    doc.moveTo(totalsX + 14, rowY + 70).lineTo(totalsX + 226, rowY + 70).stroke('#D9DEE7');
    doc.font('Helvetica-Bold').fontSize(12).fillColor('#243145');
    doc.text('Total', totalsX + 14, rowY + 76, { width: 100, align: 'left' });
    doc.text(money(draft.total), totalsX + 120, rowY + 76, { width: 100, align: 'right' });

    doc.fillColor('#687385').font('Helvetica').fontSize(8.5).text(
      'Documento generado por FULLTECH. Verifique cantidades, precios y datos del cliente antes de compartirlo.',
      doc.page.margins.left,
      doc.page.height - doc.page.margins.bottom - 10,
      { width: pageWidth, align: 'center' },
    );
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