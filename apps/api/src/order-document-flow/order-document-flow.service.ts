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
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { EvolutionWhatsAppService } from '../notifications/evolution-whatsapp.service';
import { NotificationsService } from '../notifications/notifications.service';
import { PrismaService } from '../prisma/prisma.service';
import {
  SERVICE_ORDER_CATEGORY_FROM_DB,
  SERVICE_ORDER_TYPE_FROM_DB,
} from '../service-orders/service-orders.constants';
import { EditOrderDocumentFlowDraftDto } from './dto/edit-order-document-flow-draft.dto';
import { SendOrderDocumentFlowDto } from './dto/send-order-document-flow.dto';

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

  constructor(
    private readonly prisma: PrismaService,
    private readonly evolutionWhatsApp: EvolutionWhatsAppService,
    private readonly notifications: NotificationsService,
  ) {}

  private readonly include = {
    order: {
      include: {
        client: true,
        createdBy: {
          select: {
            id: true,
            nombreCompleto: true,
            telefono: true,
            numeroFlota: true,
            blocked: true,
          },
        },
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

  async send(user: AuthUser, id: string, dto: SendOrderDocumentFlowDto = {}) {
    this.assertAssistantOrAdmin(user);
    let flow = await this.findFlowById(id);
    const customerPhone = this.toText(flow.order.client.telefono);
    const customerName = this.toText(flow.order.client.nombre, 'Cliente');

    if (!customerPhone) {
      throw new BadRequestException('La orden no tiene un teléfono de cliente válido para WhatsApp.');
    }

    const providedInvoiceBytes = this.parsePdfBase64(dto.invoicePdfBase64, 'la factura');
    const providedWarrantyBytes = this.parsePdfBase64(dto.warrantyPdfBase64, 'la carta de garantia');
    const hasProvidedPdfs = !!providedInvoiceBytes && !!providedWarrantyBytes;

    if (!hasProvidedPdfs && (!flow.invoiceFinalUrl || !flow.warrantyFinalUrl)) {
      await this.generate(user, id);
      flow = await this.findFlowById(id);
    }

    if (hasProvidedPdfs) {
      flow = await this.persistProvidedFinalPdfs(flow, {
        invoiceBytes: providedInvoiceBytes,
        warrantyBytes: providedWarrantyBytes,
        invoiceFileName: this.toText(dto.invoiceFileName, 'factura-final.pdf'),
        warrantyFileName: this.toText(dto.warrantyFileName, 'warranty-final.pdf'),
      });
    }

    const invoiceFinalUrl = this.toText(flow.invoiceFinalUrl);
    const warrantyFinalUrl = this.toText(flow.warrantyFinalUrl);
    if (!invoiceFinalUrl || !warrantyFinalUrl) {
      throw new BadRequestException('No fue posible generar la factura y la carta de garantía para enviar.');
    }

    const invoiceBytes = readFileSync(this.resolveUploadAbsolutePath(invoiceFinalUrl));
    const warrantyBytes = readFileSync(this.resolveUploadAbsolutePath(warrantyFinalUrl));
    const messageText = [
      `Hola ${customerName},`,
      'Gracias por su preferencia. Aqui esta su factura.',
      'Debajo tambien le compartimos la carta de garantia correspondiente a su servicio.',
    ].join('\n');

    await this.evolutionWhatsApp.sendTextMessage({
      toNumber: customerPhone,
      message: messageText,
      senderUserId: flow.order.createdBy.id,
      requirePersonalInstance: true,
    });
    await this.evolutionWhatsApp.sendPdfDocument({
      toNumber: customerPhone,
      bytes: invoiceBytes,
      fileName: this.buildDocumentFileName('factura', flow.order.id),
      caption: 'Factura correspondiente a su servicio.',
      senderUserId: flow.order.createdBy.id,
      requirePersonalInstance: true,
    });
    await this.evolutionWhatsApp.sendPdfDocument({
      toNumber: customerPhone,
      bytes: warrantyBytes,
      fileName: this.buildDocumentFileName('carta_garantia', flow.order.id),
      caption: 'Carta de garantia correspondiente a su servicio.',
      senderUserId: flow.order.createdBy.id,
      requirePersonalInstance: true,
    });

    const updated = await this.prisma.orderDocumentFlow.update({
      where: { id },
      include: this.include,
      data: {
        status: OrderDocumentFlowStatus.SENT,
        sentAt: new Date(),
      },
    });

    const mapped = this.mapFlow(updated);
    const normalizedPhone = this.evolutionWhatsApp.normalizeWhatsAppNumber(customerPhone);
    this.logger.log(
      `Document flow WhatsApp sent by user=${user.id} role=${user.role} to=${normalizedPhone || customerPhone} flow=${id}`,
    );

    if (flow.order.createdBy?.id) {
      const internalMessage = [
        '*Documentos enviados al cliente*',
        `Cliente: ${customerName}`,
        `Teléfono: ${normalizedPhone || customerPhone}`,
        'Se enviaron la factura y la carta de garantía desde la instancia principal de empresa.',
      ].join('\n');

      await this.notifications.enqueueWhatsAppToUser({
        recipientUserId: flow.order.createdBy.id,
        payload: {
          template: 'custom_text',
          title: 'Documentos enviados al cliente',
          body: internalMessage,
          data: {
            kind: 'order_document_flow_sent',
            orderId: flow.order.id,
            flowId: flow.id,
            customerPhone: normalizedPhone || customerPhone,
          },
        } as any,
        dedupeKey: `order-document-flow:sent:${flow.id}:${flow.order.createdBy.id}`,
        senderUserId: flow.order.createdBy.id,
      });
    }

    return {
      flow: mapped,
      whatsappPayload: {
        toNumber: normalizedPhone || customerPhone,
        messageText,
        attachments: [mapped.invoiceFinalUrl, mapped.warrantyFinalUrl].filter(
          (value): value is string => typeof value === 'string' && value.length > 0,
        ),
      },
    };
  }

  async remove(user: AuthUser, id: string) {
    this.assertAssistantOrAdmin(user);
    const flow = await this.findFlowById(id);

    await this.prisma.orderDocumentFlow.delete({
      where: { id },
    });

    this.deleteGeneratedArtifacts(flow.id);

    return {
      ok: true,
      id: flow.id,
      orderId: flow.orderId,
    };
  }

  async syncFromServiceOrderStatus(orderId: string, status: ServiceOrderStatus) {
    if (status === ServiceOrderStatus.EN_PROCESO) {
      const current = await this.ensureFlowCreatedForOrder(orderId);
      if (
        current.status !== OrderDocumentFlowStatus.APPROVED &&
        current.status !== OrderDocumentFlowStatus.SENT &&
        current.status !== OrderDocumentFlowStatus.READY_FOR_FINALIZATION
      ) {
        await this.prisma.orderDocumentFlow.update({
          where: { id: current.id },
          data: {
            status: OrderDocumentFlowStatus.READY_FOR_REVIEW,
          },
        });
      }
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

  private deleteGeneratedArtifacts(flowId: string) {
    const relativeDir = join('document-flows', flowId).replace(/\\/g, '/');
    const absoluteDir = this.buildAbsoluteUploadPath(relativeDir);

    try {
      if (existsSync(absoluteDir)) {
        rmSync(absoluteDir, { recursive: true, force: true });
      }
    } catch (error) {
      this.logger.warn(`No se pudieron limpiar archivos del flujo documental ${flowId}: ${error}`);
    }
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
    const currencyLabel = this.toText(draft.currency, 'RD$');
    const quotationLabel = this.toText(flow.order.quotationId).slice(0, 8).toUpperCase();
    const customerAddress = this.toText(flow.order.client.direccion);
    const items = draft.items.length > 0
      ? draft.items
      : [{
          description: this.toText(flow.order.serviceType, 'Servicio tecnico finalizado'),
          qty: 1,
          unitPrice: draft.total,
          lineTotal: draft.total,
        }];
    const money = (value: number) => `${currencyLabel} ${value.toFixed(2)}`;
    const quantity = (value: number) => value % 1 === 0 ? value.toFixed(0) : value.toFixed(2);
    const formatDate = (value: Date) => {
      const day = `${value.getDate()}`.padStart(2, '0');
      const month = `${value.getMonth() + 1}`.padStart(2, '0');
      const year = value.getFullYear();
      return `${day}/${month}/${year}`;
    };

    const doc = new PDFDocument({ margin: 40, size: 'A4' });
    const chunks: Buffer[] = [];
    const pdfBuffer = new Promise<Buffer>((resolve, reject) => {
      doc.on('data', (chunk) => chunks.push(Buffer.from(chunk)));
      doc.on('end', () => resolve(Buffer.concat(chunks)));
      doc.on('error', reject);
    });

    const logoBuffer = this.decodeLogoBase64(company.logoBase64);
    const pageWidth = doc.page.width - doc.page.margins.left - doc.page.margins.right;
    const tableWidth = pageWidth;
    const left = doc.page.margins.left;
    const contentBottom = () => doc.page.height - doc.page.margins.bottom - 48;
    const columnIndexWidth = 34;
    const columnQtyWidth = 56;
    const columnPriceWidth = 96;
    const columnAmountWidth = 104;
    const descriptionWidth = tableWidth - columnIndexWidth - columnQtyWidth - columnPriceWidth - columnAmountWidth;
    let currentPage = 1;

    const drawFooter = () => {
      const footerY = doc.page.height - doc.page.margins.bottom + 8;
      doc.save();
      doc.moveTo(left, footerY - 10).lineTo(left + pageWidth, footerY - 10).stroke('#D9E1EA');
      doc.restore();
      doc.fillColor('#687385').font('Helvetica').fontSize(8);
      doc.text(
        'Factura comercial generada por FULLTECH. Verifique datos del cliente, cantidades y montos antes de compartirla.',
        left,
        footerY,
        { width: pageWidth - 80, align: 'left' },
      );
      doc.text(`Pagina ${currentPage}`, left + pageWidth - 60, footerY, {
        width: 60,
        align: 'right',
      });
    };

    const drawHeader = (continuation = false) => {
      const top = doc.page.margins.top;
      const companyBlockWidth = 315;
      const invoiceBlockWidth = pageWidth - companyBlockWidth - 14;

      doc.save();
      doc.roundedRect(left, top, pageWidth, 108, 18).fill('#243145');
      doc.restore();

      doc.save();
      doc.roundedRect(left + companyBlockWidth + 14, top + 14, invoiceBlockWidth - 14, 80, 14).fill('#FFFFFF');
      doc.restore();

      if (logoBuffer) {
        try {
          doc.image(logoBuffer, left + 16, top + 20, {
            fit: [64, 64],
            valign: 'center',
          });
        } catch (error) {
          this.logger.warn(`No se pudo insertar logo en factura PDF: ${error}`);
        }
      }

      const textStartX = left + (logoBuffer ? 92 : 18);
      doc.fillColor('#FFFFFF').font('Helvetica-Bold').fontSize(19).text(company.companyName, textStartX, top + 18, {
        width: companyBlockWidth - (textStartX - left) - 12,
        align: 'left',
      });
      const companyLines = [
        company.rnc.length > 0 ? `RNC: ${company.rnc}` : '',
        company.phone.length > 0 ? `Tel: ${company.phone}` : '',
        company.address,
      ].filter((value) => value.trim().length > 0);
      let companyLineY = top + 44;
      doc.font('Helvetica').fontSize(9.2).fillColor('#D8E1F0');
      for (const line of companyLines) {
        doc.text(line, textStartX, companyLineY, {
          width: companyBlockWidth - (textStartX - left) - 12,
          align: 'left',
        });
        companyLineY += 12;
      }

      doc.fillColor('#243145').font('Helvetica-Bold').fontSize(16).text('FACTURA', left + companyBlockWidth + 28, top + 24, {
        width: invoiceBlockWidth - 42,
        align: 'left',
      });
      const metaLines = [
        `Factura No.: ${invoiceNumber}`,
        `Fecha de emision: ${formatDate(issueDate)}`,
        `Moneda: ${draft.currency}`,
        continuation ? 'Documento continuado' : 'Factura comercial',
      ];
      let metaLineY = top + 48;
      doc.font('Helvetica').fontSize(9.5).fillColor('#243145');
      for (const line of metaLines) {
        doc.text(line, left + companyBlockWidth + 28, metaLineY, {
          width: invoiceBlockWidth - 42,
          align: 'left',
        });
        metaLineY += 12;
      }

      const infoTop = top + 126;
      const panelGap = 12;
      const panelWidth = (pageWidth - panelGap) / 2;

      doc.save();
      doc.roundedRect(left, infoTop, panelWidth, 92, 14).fill('#F8FAFC');
      doc.roundedRect(left + panelWidth + panelGap, infoTop, panelWidth, 92, 14).fill('#F8FAFC');
      doc.restore();
      doc.roundedRect(left, infoTop, panelWidth, 92, 14).stroke('#E1E8F0');
      doc.roundedRect(left + panelWidth + panelGap, infoTop, panelWidth, 92, 14).stroke('#E1E8F0');

      doc.fillColor('#243145').font('Helvetica-Bold').fontSize(11).text('Facturar a', left + 14, infoTop + 14, {
        width: panelWidth - 28,
      });
      const clientLines = [
        draft.clientName,
        draft.clientPhone.length > 0 ? `Tel: ${draft.clientPhone}` : '',
        customerAddress,
      ].filter((value) => value.trim().length > 0);
      let clientY = infoTop + 34;
      doc.font('Helvetica').fontSize(10).fillColor('#1F2430');
      for (const line of clientLines) {
        doc.text(line, left + 14, clientY, { width: panelWidth - 28, align: 'left' });
        clientY += 13;
      }

      const referenceX = left + panelWidth + panelGap + 14;
      doc.fillColor('#243145').font('Helvetica-Bold').fontSize(11).text('Datos de la orden', referenceX, infoTop + 14, {
        width: panelWidth - 28,
      });
      const referenceLines = [
        `Orden: ${draft.orderId}`,
        quotationLabel.length > 0 ? `Cotizacion: ${quotationLabel}` : 'Cotizacion: no vinculada',
        `Estado: ${this.toText(flow.order.status, 'SIN ESTADO')}`,
        this.toText(flow.order.serviceType).length > 0 ? `Servicio: ${this.toText(flow.order.serviceType)}` : '',
      ].filter((value) => value.trim().length > 0);
      let referenceY = infoTop + 34;
      doc.font('Helvetica').fontSize(10).fillColor('#1F2430');
      for (const line of referenceLines) {
        doc.text(line, referenceX, referenceY, { width: panelWidth - 28, align: 'left' });
        referenceY += 13;
      }

      doc.y = infoTop + 112;
    };

    const drawTableHeader = () => {
      const top = doc.y;
      doc.save();
      doc.roundedRect(left, top, tableWidth, 26, 8).fill('#EAF1FF');
      doc.restore();
      doc.fillColor('#243145').font('Helvetica-Bold').fontSize(10);
      doc.text('#', left + 8, top + 8, { width: columnIndexWidth - 10, align: 'center' });
      doc.text('Detalle', left + columnIndexWidth + 8, top + 8, {
        width: descriptionWidth - 16,
        align: 'left',
      });
      doc.text('Cant.', left + columnIndexWidth + descriptionWidth, top + 8, {
        width: columnQtyWidth,
        align: 'center',
      });
      doc.text('Precio unitario', left + columnIndexWidth + descriptionWidth + columnQtyWidth, top + 8, {
        width: columnPriceWidth - 10,
        align: 'right',
      });
      doc.text('Importe', left + columnIndexWidth + descriptionWidth + columnQtyWidth + columnPriceWidth, top + 8, {
        width: columnAmountWidth - 12,
        align: 'right',
      });
      doc.y = top + 34;
    };

    const ensureSpace = (height: number, redrawTable = false) => {
      if (doc.y + height <= contentBottom()) return;
      drawFooter();
      doc.addPage();
      currentPage += 1;
      drawHeader(true);
      if (redrawTable) {
        drawTableHeader();
      }
    };

    drawHeader();
    drawTableHeader();

    items.forEach((item, index) => {
      const descriptionHeight = doc.heightOfString(item.description, {
        width: descriptionWidth - 18,
        align: 'left',
      });
      const rowHeight = Math.max(30, descriptionHeight + 14);
      ensureSpace(rowHeight + 8, true);
      const rowTop = doc.y;

      doc.save();
      doc.roundedRect(left, rowTop, tableWidth, rowHeight, 8).fill(index % 2 === 0 ? '#FFFFFF' : '#F8FAFC');
      doc.restore();
      doc.roundedRect(left, rowTop, tableWidth, rowHeight, 8).stroke('#E3EAF2');

      doc.fillColor('#1F2430').font('Helvetica').fontSize(10);
      doc.text(`${index + 1}`, left + 8, rowTop + 9, {
        width: columnIndexWidth - 10,
        align: 'center',
      });
      doc.text(item.description, left + columnIndexWidth + 8, rowTop + 8, {
        width: descriptionWidth - 16,
        align: 'left',
      });
      doc.text(quantity(item.qty), left + columnIndexWidth + descriptionWidth, rowTop + 9, {
        width: columnQtyWidth,
        align: 'center',
      });
      doc.text(money(item.unitPrice), left + columnIndexWidth + descriptionWidth + columnQtyWidth, rowTop + 9, {
        width: columnPriceWidth - 10,
        align: 'right',
      });
      doc.font('Helvetica-Bold').text(
        money(item.lineTotal),
        left + columnIndexWidth + descriptionWidth + columnQtyWidth + columnPriceWidth,
        rowTop + 9,
        {
          width: columnAmountWidth - 12,
          align: 'right',
        },
      );
      doc.y = rowTop + rowHeight + 8;
    });

    const notesText = this.toText(draft.notes, 'Sin observaciones adicionales.');
    const notesWidth = 278;
    const totalsGap = 14;
    const totalsWidth = pageWidth - notesWidth - totalsGap;
    const notesHeight = Math.max(88, doc.heightOfString(notesText, { width: notesWidth - 24 }) + 38);
    const totalsHeight = 126;
    ensureSpace(Math.max(notesHeight, totalsHeight) + 18, false);

    const sectionTop = doc.y + 2;
    doc.save();
    doc.roundedRect(left, sectionTop, notesWidth, notesHeight, 14).fill('#FFFFFF');
    doc.roundedRect(left + notesWidth + totalsGap, sectionTop, totalsWidth, totalsHeight, 14).fill('#F8FAFC');
    doc.restore();
    doc.roundedRect(left, sectionTop, notesWidth, notesHeight, 14).stroke('#E3EAF2');
    doc.roundedRect(left + notesWidth + totalsGap, sectionTop, totalsWidth, totalsHeight, 14).stroke('#D7E4FF');

    doc.fillColor('#243145').font('Helvetica-Bold').fontSize(11).text('Observaciones', left + 14, sectionTop + 16, {
      width: notesWidth - 28,
      align: 'left',
    });
    doc.fillColor('#1F2430').font('Helvetica').fontSize(10).text(notesText, left + 14, sectionTop + 34, {
      width: notesWidth - 28,
      align: 'left',
    });

    const totalsX = left + notesWidth + totalsGap + 14;
    const valueX = left + notesWidth + totalsGap + totalsWidth - 14;
    doc.fillColor('#243145').font('Helvetica-Bold').fontSize(11).text('Totales de factura', totalsX, sectionTop + 16, {
      width: totalsWidth - 28,
      align: 'left',
    });
    doc.fillColor('#1F2430').font('Helvetica').fontSize(10);
    doc.text('Subtotal', totalsX, sectionTop + 44, { width: 90, align: 'left' });
    doc.text(money(draft.subtotal), valueX - 110, sectionTop + 44, { width: 110, align: 'right' });
    doc.text('Impuesto', totalsX, sectionTop + 62, { width: 90, align: 'left' });
    doc.text(money(draft.tax), valueX - 110, sectionTop + 62, { width: 110, align: 'right' });
    doc.moveTo(totalsX, sectionTop + 84).lineTo(valueX, sectionTop + 84).stroke('#CAD8F5');
    doc.save();
    doc.roundedRect(totalsX, sectionTop + 92, totalsWidth - 28, 22, 8).fill('#EAF1FF');
    doc.restore();
    doc.fillColor('#243145').font('Helvetica-Bold').fontSize(11).text('TOTAL', totalsX + 10, sectionTop + 99, {
      width: 80,
      align: 'left',
    });
    doc.text(money(draft.total), valueX - 120, sectionTop + 99, { width: 120, align: 'right' });

    doc.fillColor('#687385').font('Helvetica').fontSize(8.4).text(
      'Gracias por confiar en FULLTECH. Este documento respalda los trabajos y conceptos incluidos en la orden de servicio.',
      left,
      sectionTop + Math.max(notesHeight, totalsHeight) + 14,
      { width: pageWidth, align: 'center' },
    );

    drawFooter();
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

  private parsePdfBase64(value: string | undefined, label: string) {
    const trimmed = (value ?? '').trim();
    if (!trimmed) {
      return null;
    }

    const base64 = trimmed.startsWith('data:')
      ? trimmed.slice(trimmed.indexOf(',') + 1)
      : trimmed;

    let bytes: Buffer;
    try {
      bytes = Buffer.from(base64, 'base64');
    } catch {
      throw new BadRequestException(`El PDF de ${label} no es válido.`);
    }

    if (!bytes.length) {
      throw new BadRequestException(`El PDF de ${label} llegó vacío.`);
    }

    return bytes;
  }

  private async persistProvidedFinalPdfs(
    flow: DocumentFlowRow,
    params: {
      invoiceBytes: Buffer;
      warrantyBytes: Buffer;
      invoiceFileName: string;
      warrantyFileName: string;
    },
  ) {
    const invoiceRelativePath = join(
      'document-flows',
      flow.id,
      this.toText(params.invoiceFileName, 'factura-final.pdf'),
    ).replace(/\\/g, '/');
    const warrantyRelativePath = join(
      'document-flows',
      flow.id,
      this.toText(params.warrantyFileName, 'warranty-final.pdf'),
    ).replace(/\\/g, '/');

    writeFileSync(this.buildAbsoluteUploadPath(invoiceRelativePath), params.invoiceBytes);
    writeFileSync(this.buildAbsoluteUploadPath(warrantyRelativePath), params.warrantyBytes);

    const updated = await this.prisma.orderDocumentFlow.update({
      where: { id: flow.id },
      include: this.include,
      data: {
        invoiceFinalUrl: `/${join('uploads', invoiceRelativePath).replace(/\\/g, '/')}`,
        warrantyFinalUrl: `/${join('uploads', warrantyRelativePath).replace(/\\/g, '/')}`,
        status: OrderDocumentFlowStatus.APPROVED,
      },
    });

    return updated;
  }

  private resolveUploadAbsolutePath(documentUrl: string) {
    const normalized = this.toText(documentUrl)
      .replace(/\\/g, '/')
      .replace(/^\/+/, '');
    const relativePath = normalized.startsWith('uploads/')
      ? normalized.slice('uploads/'.length)
      : normalized;
    return this.buildAbsoluteUploadPath(relativePath);
  }

  private buildDocumentFileName(prefix: string, orderId: string) {
    const normalizedOrderId = this.toText(orderId).replace(/[^a-zA-Z0-9_-]/g, '');
    const suffix = normalizedOrderId.slice(0, 8) || 'documento';
    return `${prefix}_${suffix}.pdf`;
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