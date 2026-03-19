import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import {
  Prisma,
  Role,
  ServiceClosingApprovalStatus,
  ServiceClosingSignatureStatus,
  ServiceUpdateType,
  ServiceStatus,
  WarrantyDurationUnit,
} from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { R2Service } from '../storage/r2.service';
import { buildInvoicePdf, buildWarrantyPdf, InvoiceDraftData, WarrantyDraftData } from './pdf/pdf-builders';
import { WarrantyConfigResolution, WarrantyConfigsService } from '../warranty-configs/warranty-configs.service';

type AuthUser = { id: string; role: Role };

function isHttpUrl(v: string) {
  return v.startsWith('http://') || v.startsWith('https://');
}

function safeNumber(v: unknown): number {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (typeof v === 'string') {
    const n = Number(v);
    return Number.isFinite(n) ? n : 0;
  }
  if (v && typeof v === 'object') {
    const anyV = v as any;
    if (typeof anyV.toNumber === 'function') {
      const n = anyV.toNumber();
      return Number.isFinite(n) ? n : 0;
    }
    if (typeof anyV.toString === 'function') {
      const n = Number(anyV.toString());
      return Number.isFinite(n) ? n : 0;
    }
  }
  return 0;
}

@Injectable()
export class ServiceClosingService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly notifications: NotificationsService,
    private readonly r2: R2Service,
    private readonly warrantyConfigs: WarrantyConfigsService,
  ) {}

  private isSchemaMismatch(error: unknown) {
    const msg = (error as any)?.message ? String((error as any).message) : String(error);
    return /prisma/i.test(msg) && /(does not exist|unknown.*field|column .* does not exist|relation .* does not exist)/i.test(msg);
  }

  private isAdminLike(role: Role) {
    return role === Role.ADMIN || role === Role.ASISTENTE;
  }

  private assertAdminApproval(user: AuthUser) {
    if (this.isAdminLike(user.role)) return;
    throw new ForbiddenException('No autorizado');
  }

  private async getServiceOrThrow(user: AuthUser, serviceId: string, mode: 'view' | 'operate') {
    const service = await this.prisma.service.findFirst({
      where: { id: serviceId, isDeleted: false },
      include: { assignments: true },
    });
    if (!service) throw new NotFoundException('Servicio no encontrado');

    const assignedIds = (service.assignments ?? []).map((a) => a.userId);
    const sellerId = service.createdByUserId;

    const canView = () => {
      if (this.isAdminLike(user.role)) return true;
      if (user.role === Role.VENDEDOR && user.id === sellerId) return true;
      if (user.role === Role.TECNICO && assignedIds.includes(user.id)) return true;
      return false;
    };

    const canOperate = () => {
      if (this.isAdminLike(user.role)) return true;
      if (user.role === Role.VENDEDOR && user.id === sellerId) return true;
      if (user.role === Role.TECNICO && assignedIds.includes(user.id)) return true;
      return false;
    };

    if (mode === 'view' && !canView()) throw new ForbiddenException('No autorizado para ver este servicio');
    if (mode === 'operate' && !canOperate()) throw new ForbiddenException('No autorizado para modificar este servicio');

    return service;
  }

  async getSummaryBestEffort(serviceId: string) {
    try {
      const row = await this.prisma.serviceClosing.findUnique({
        where: { serviceId },
        select: {
          serviceId: true,
          approvalStatus: true,
          signatureStatus: true,
          invoiceDraftFileId: true,
          warrantyDraftFileId: true,
          invoiceApprovedFileId: true,
          warrantyApprovedFileId: true,
          invoiceFinalFileId: true,
          warrantyFinalFileId: true,
          approvedAt: true,
          signedAt: true,
          sentToClientAt: true,
        },
      });
      return row;
    } catch (e) {
      if (this.isSchemaMismatch(e)) return null;
      throw e;
    }
  }

  private async resolveCompanyInfo() {
    try {
      const cfg = await this.prisma.appConfig.findUnique({
        where: { id: 'global' },
        select: { companyName: true, rnc: true, phone: true, address: true },
      });
      return {
        name: (cfg?.companyName ?? '').trim() || 'FULLTECH',
        rnc: (cfg?.rnc ?? '').trim() || null,
        phone: (cfg?.phone ?? '').trim() || null,
        address: (cfg?.address ?? '').trim() || null,
      };
    } catch {
      return { name: 'FULLTECH', rnc: null, phone: null, address: null };
    }
  }

  private toServiceTypeLabel(serviceType: any) {
    switch (serviceType) {
      case 'INSTALLATION':
        return 'Instalación';
      case 'MAINTENANCE':
        return 'Mantenimiento';
      case 'WARRANTY':
        return 'Garantía';
      case 'POS_SUPPORT':
        return 'Soporte POS';
      default:
        return 'Servicio';
    }
  }

  private async getSignatureFileFromExecutionReport(serviceId: string): Promise<{ fileId: string; signedAtIso?: string | null } | null> {
    try {
      const report = await this.prisma.serviceExecutionReport.findFirst({
        where: { serviceId },
        orderBy: { updatedAt: 'desc' },
        select: { phaseSpecificData: true },
      });
      const data: any = report?.phaseSpecificData as any;
      const sig = data?.clientSignature;
      const fileId = typeof sig?.fileId === 'string' ? sig.fileId.trim() : '';
      if (!fileId) return null;
      const signedAtIso = typeof sig?.signedAt === 'string' ? sig.signedAt : null;
      return { fileId, signedAtIso };
    } catch (e) {
      if (this.isSchemaMismatch(e)) return null;
      throw e;
    }
  }

  private async downloadServiceFileBytes(fileId: string): Promise<Buffer | null> {
    const row = await this.prisma.serviceFile.findUnique({
      where: { id: fileId },
      select: { storageProvider: true, objectKey: true, fileUrl: true, mimeType: true },
    });
    if (!row) return null;

    const provider = (row.storageProvider ?? '').trim();
    const objectKey = (row.objectKey ?? '').trim();
    let url = (row.fileUrl ?? '').trim();

    if (provider === 'R2' && objectKey && !isHttpUrl(url)) {
      try {
        url = await this.r2.createPresignedGetUrl({ objectKey, expiresInSeconds: 900 });
      } catch {
        url = '';
      }
    }

    if (!url || !isHttpUrl(url)) return null;

    const res = await fetch(url);
    if (!res.ok) return null;
    const arr = new Uint8Array(await res.arrayBuffer());
    return Buffer.from(arr);
  }

  private async uploadPdfToR2(params: { serviceId: string; fileName: string; pdfBytes: Buffer }) {
    const safeName = params.fileName.replace(/[^a-zA-Z0-9_.-]+/g, '_');
    const objectKey = `services/${params.serviceId}/docs/${Date.now()}_${safeName}`;

    await this.r2.putObject({
      objectKey,
      body: params.pdfBytes,
      contentType: 'application/pdf',
    });

    return {
      safeName,
      objectKey,
      publicUrl: this.r2.buildPublicUrl(objectKey),
      size: params.pdfBytes.length,
    };
  }

  private createServiceFileRowForUploadedPdf(
    db: Prisma.TransactionClient | PrismaService,
    params: {
      serviceId: string;
      uploadedByUserId: string;
      kind: string;
      caption?: string | null;
      upload: { safeName: string; objectKey: string; publicUrl: string; size: number };
    },
  ) {
    return db.serviceFile.create({
      data: {
        serviceId: params.serviceId,
        uploadedByUserId: params.uploadedByUserId,
        fileUrl: params.upload.publicUrl,
        fileType: params.kind,
        caption: (params.caption ?? '').trim() || null,
        storageProvider: 'R2',
        objectKey: params.upload.objectKey,
        originalFileName: params.upload.safeName,
        mimeType: 'application/pdf',
        mediaType: 'document',
        kind: params.kind,
        fileSize: params.upload.size,
      },
    });
  }

  private async uploadPdfAsServiceFile(params: {
    serviceId: string;
    uploadedByUserId: string;
    kind: string;
    fileName: string;
    pdfBytes: Buffer;
    caption?: string | null;
  }) {
    const upload = await this.uploadPdfToR2({
      serviceId: params.serviceId,
      fileName: params.fileName,
      pdfBytes: params.pdfBytes,
    });
    return this.createServiceFileRowForUploadedPdf(this.prisma, {
      serviceId: params.serviceId,
      uploadedByUserId: params.uploadedByUserId,
      kind: params.kind,
      caption: params.caption,
      upload,
    });
  }

  private durationValueFromResolution(resolution: WarrantyConfigResolution | null) {
    return resolution?.hasWarranty === false ? null : (resolution?.durationValue ?? null);
  }

  private durationUnitFromResolution(resolution: WarrantyConfigResolution | null) {
    if (resolution?.hasWarranty === false) return null;
    return (resolution?.durationUnit ?? WarrantyDurationUnit.MONTHS) as 'DAYS' | 'MONTHS' | 'YEARS' | null;
  }

  private buildWarrantyFallbackSummary(serviceTypeLabel: string) {
    return `Garantia operativa para ${serviceTypeLabel.toLowerCase()} sujeta a revision tecnica, validacion del caso y condiciones normales de uso.`;
  }

  private async resolveWarrantyDraftContext(params: {
    createdByUserId: string;
    categoryId?: string | null;
    category?: string | null;
    serviceTitle?: string | null;
    equipmentInstalledText?: string | null;
  }) {
    return this.warrantyConfigs.resolveForService({
      fallbackUserId: params.createdByUserId,
      categoryId: params.categoryId,
      categoryCode: params.category,
      categoryName: params.category,
      serviceTitle: params.serviceTitle,
      equipmentInstalledText: params.equipmentInstalledText,
    });
  }

  private async buildDraftDataFromService(serviceId: string) {
    const service = await this.prisma.service.findFirst({
      where: { id: serviceId, isDeleted: false },
      include: {
        customer: true,
        technician: { select: { id: true, nombreCompleto: true, telefono: true } },
      },
    });
    if (!service) throw new NotFoundException('Servicio no encontrado');

    const company = await this.resolveCompanyInfo();

    const changes = await this.prisma.serviceExecutionChange.findMany({
      where: { serviceId: service.id },
      orderBy: { createdAt: 'asc' },
      select: { description: true, quantity: true, extraCost: true, note: true },
    });

    const extras = changes
      .map((c) => ({
        description: (c.description ?? '').trim() || 'Extra',
        qty: c.quantity != null ? safeNumber(c.quantity) : null,
        amount: safeNumber(c.extraCost),
        note: (c.note ?? '').trim() || null,
      }))
      .filter((x) => x.amount > 0 || x.description);

    const quotedAmount = safeNumber((service as any).quotedAmount);
    const extrasTotal = extras.reduce((acc, x) => acc + safeNumber(x.amount), 0);

    const orderExtras: any = (service as any).orderExtras as any;
    const finalCost = safeNumber(orderExtras?.finalCost);
    const computedTotal = quotedAmount + extrasTotal;
    const total = finalCost > 0 ? finalCost : computedTotal;

    const serviceDateIso = (service.completedAt ?? service.scheduledStart ?? service.createdAt)?.toISOString?.() ?? null;
    const equipmentInstalledText = typeof orderExtras?.materialsUsed === 'string' ? orderExtras.materialsUsed : null;
    const resolvedWarranty = await this.resolveWarrantyDraftContext({
      createdByUserId: service.createdByUserId,
      categoryId: service.categoryId,
      category: service.category,
      serviceTitle: service.title,
      equipmentInstalledText,
    });
    const serviceTypeLabel = this.toServiceTypeLabel(service.serviceType);

    const invoiceData: InvoiceDraftData = {
      company,
      invoice: {
        number: `SVC-${service.id.slice(0, 8).toUpperCase()}`,
        dateIso: new Date().toISOString(),
      },
      client: {
        name: (service.customer?.nombre ?? '').trim() || 'Cliente',
        phone: (service.customer?.telefono ?? '').trim() || null,
        address: (service.addressSnapshot ?? service.customer?.direccion ?? '').trim() || null,
      },
      service: {
        id: service.id,
        title: (service.title ?? '').trim() || 'Servicio',
        typeLabel: serviceTypeLabel,
        technicianName: (service.technician?.nombreCompleto ?? '').trim() || null,
        serviceDateIso,
      },
      initialQuoteAmount: quotedAmount,
      extras,
      notes: equipmentInstalledText,
      totals: {
        extrasTotal,
        total,
      },
      approvalRecord: null,
      signature: null,
    };

    const warrantyData: WarrantyDraftData = {
      company,
      certificate: {
        number: `GAR-${service.id.slice(0, 8).toUpperCase()}`,
        dateIso: new Date().toISOString(),
      },
      clientName: (service.customer?.nombre ?? '').trim() || 'Cliente',
      serviceTypeLabel: serviceTypeLabel,
      serviceLabel: (service.title ?? '').trim() || null,
      scopeLabel: resolvedWarranty?.scopeLabel ?? ((service.category ?? '').trim() || null),
      equipmentInstalledText,
      installationDateIso: serviceDateIso,
      hasWarranty: resolvedWarranty?.hasWarranty ?? true,
      warrantyDurationValue: this.durationValueFromResolution(resolvedWarranty),
      warrantyDurationUnit: this.durationUnitFromResolution(resolvedWarranty),
      warrantySummary: resolvedWarranty?.summary ?? this.buildWarrantyFallbackSummary(serviceTypeLabel),
      coverageSummary: resolvedWarranty?.coverageSummary ?? null,
      exclusionsSummary: resolvedWarranty?.exclusionsSummary ?? null,
      notes: resolvedWarranty?.notes ?? null,
      technicianName: (service.technician?.nombreCompleto ?? '').trim() || null,
      serviceDateIso,
      approvalRecord: null,
      signature: null,
    };

    return { service, invoiceData, warrantyData };
  }

  async ensureDraftOnPhaseEntry(params: { serviceId: string; triggeredByUserId: string }) {
    let existing: any;
    try {
      existing = await this.prisma.serviceClosing.findUnique({ where: { serviceId: params.serviceId } });
    } catch (e) {
      if (this.isSchemaMismatch(e)) {
        throw new ServiceUnavailableException('Cierre de servicio no disponible: falta aplicar migraciones.');
      }
      throw e;
    }

    if (existing?.invoiceDraftFileId && existing?.warrantyDraftFileId) return existing;

    const { invoiceData, warrantyData, service } = await this.buildDraftDataFromService(params.serviceId);
    const invoicePdf = await buildInvoicePdf(invoiceData);
    const warrantyPdf = await buildWarrantyPdf(warrantyData);

    const [invUpload, warUpload] = await Promise.all([
      this.uploadPdfToR2({
        serviceId: params.serviceId,
        fileName: `factura_${params.serviceId}.pdf`,
        pdfBytes: invoicePdf,
      }),
      this.uploadPdfToR2({
        serviceId: params.serviceId,
        fileName: `garantia_${params.serviceId}.pdf`,
        pdfBytes: warrantyPdf,
      }),
    ]);

    const updated = await this.prisma.$transaction(async (tx) => {
      const closing = existing
        ? await tx.serviceClosing.update({
            where: { serviceId: params.serviceId },
            data: {
              invoiceData: invoiceData as unknown as Prisma.InputJsonValue,
              warrantyData: warrantyData as unknown as Prisma.InputJsonValue,
            },
          })
        : await tx.serviceClosing.create({
            data: {
              serviceId: params.serviceId,
              invoiceData: invoiceData as unknown as Prisma.InputJsonValue,
              warrantyData: warrantyData as unknown as Prisma.InputJsonValue,
              approvalStatus: ServiceClosingApprovalStatus.PENDING,
              signatureStatus: ServiceClosingSignatureStatus.PENDING,
            },
          });

      const inv = await this.createServiceFileRowForUploadedPdf(tx, {
        serviceId: params.serviceId,
        uploadedByUserId: params.triggeredByUserId,
        kind: 'service_invoice_draft',
        caption: 'Factura (borrador)',
        upload: invUpload,
      });

      const war = await this.createServiceFileRowForUploadedPdf(tx, {
        serviceId: params.serviceId,
        uploadedByUserId: params.triggeredByUserId,
        kind: 'service_warranty_draft',
        caption: 'Carta de garantía (borrador)',
        upload: warUpload,
      });

      const row = await tx.serviceClosing.update({
        where: { serviceId: params.serviceId },
        data: {
          invoiceDraftFileId: inv.id,
          warrantyDraftFileId: war.id,
        },
      });

      await tx.serviceUpdate
        .create({
          data: {
            serviceId: params.serviceId,
            changedByUserId: params.triggeredByUserId,
            type: ServiceUpdateType.NOTE,
            message: 'Factura y garantía generadas (borrador).',
            oldValue: Prisma.DbNull,
            newValue: { closingId: closing.id, invoiceDraftFileId: inv.id, warrantyDraftFileId: war.id } as any,
          },
        })
        .catch(() => null);

      return row;
    });

    // Best-effort: keep client last activity updated on doc generation.
    try {
      if (service?.customerId) {
        await this.prisma.client.update({
          where: { id: service.customerId },
          data: { lastActivityAt: new Date() },
        });
      }
    } catch {
      // ignore
    }

    return updated;
  }

  async refreshDraftIfPending(params: { serviceId: string; triggeredByUserId: string }) {
    let closing: any;
    try {
      closing = await this.prisma.serviceClosing.findUnique({ where: { serviceId: params.serviceId } });
    } catch (e) {
      if (this.isSchemaMismatch(e)) return null;
      throw e;
    }

    if (!closing) return null;
    if (closing.approvalStatus !== ServiceClosingApprovalStatus.PENDING) return closing;

    const { invoiceData, warrantyData } = await this.buildDraftDataFromService(params.serviceId);
    const invoicePdf = await buildInvoicePdf(invoiceData);
    const warrantyPdf = await buildWarrantyPdf(warrantyData);

    const [invUpload, warUpload] = await Promise.all([
      this.uploadPdfToR2({
        serviceId: params.serviceId,
        fileName: `factura_${params.serviceId}.pdf`,
        pdfBytes: invoicePdf,
      }),
      this.uploadPdfToR2({
        serviceId: params.serviceId,
        fileName: `garantia_${params.serviceId}.pdf`,
        pdfBytes: warrantyPdf,
      }),
    ]);

    const updated = await this.prisma.$transaction(async (tx) => {
      const inv = await this.createServiceFileRowForUploadedPdf(tx, {
        serviceId: params.serviceId,
        uploadedByUserId: params.triggeredByUserId,
        kind: 'service_invoice_draft',
        caption: 'Factura (borrador - actualizado)',
        upload: invUpload,
      });

      const war = await this.createServiceFileRowForUploadedPdf(tx, {
        serviceId: params.serviceId,
        uploadedByUserId: params.triggeredByUserId,
        kind: 'service_warranty_draft',
        caption: 'Carta de garantía (borrador - actualizado)',
        upload: warUpload,
      });

      return tx.serviceClosing.update({
        where: { serviceId: params.serviceId },
        data: {
          invoiceData: invoiceData as unknown as Prisma.InputJsonValue,
          warrantyData: warrantyData as unknown as Prisma.InputJsonValue,
          invoiceDraftFileId: inv.id,
          warrantyDraftFileId: war.id,
        },
      });
    });

    return updated;
  }

  async tryStartOnServiceFinalized(params: { serviceId: string; triggeredByUserId: string }) {
    // Idempotent start: if already exists, no-op.
    try {
      const existing = await this.prisma.serviceClosing.findUnique({ where: { serviceId: params.serviceId } });
      if (existing) return existing;
    } catch (e) {
      if (this.isSchemaMismatch(e)) {
        // Server missing migrations; don't block service completion.
        return null;
      }
      throw e;
    }

    const { service, invoiceData, warrantyData } = await this.buildDraftDataFromService(params.serviceId);

    let closing: any;
    try {
      closing = await this.prisma.serviceClosing.create({
        data: {
          serviceId: service.id,
          invoiceData: invoiceData as unknown as Prisma.InputJsonValue,
          warrantyData: warrantyData as unknown as Prisma.InputJsonValue,
          approvalStatus: ServiceClosingApprovalStatus.PENDING,
          signatureStatus: ServiceClosingSignatureStatus.PENDING,
        },
      });
    } catch (e) {
      if (this.isSchemaMismatch(e)) {
        throw new ServiceUnavailableException('Cierre de servicio no disponible: falta aplicar migraciones.');
      }
      throw e;
    }

    // Generate draft PDFs.
    const invoicePdf = await buildInvoicePdf(invoiceData);
    const warrantyPdf = await buildWarrantyPdf(warrantyData);

    const [invUpload, warUpload] = await Promise.all([
      this.uploadPdfToR2({
        serviceId: service.id,
        fileName: `factura_${service.id}.pdf`,
        pdfBytes: invoicePdf,
      }),
      this.uploadPdfToR2({
        serviceId: service.id,
        fileName: `garantia_${service.id}.pdf`,
        pdfBytes: warrantyPdf,
      }),
    ]);

    const [invFile, warFile] = await this.prisma.$transaction(async (tx) => {
      const inv = await this.createServiceFileRowForUploadedPdf(tx, {
        serviceId: service.id,
        uploadedByUserId: params.triggeredByUserId,
        kind: 'service_invoice_draft',
        caption: 'Factura (borrador)',
        upload: invUpload,
      });

      const war = await this.createServiceFileRowForUploadedPdf(tx, {
        serviceId: service.id,
        uploadedByUserId: params.triggeredByUserId,
        kind: 'service_warranty_draft',
        caption: 'Carta de garantía (borrador)',
        upload: warUpload,
      });

      const updated = await tx.serviceClosing.update({
        where: { serviceId: service.id },
        data: {
          invoiceDraftFileId: inv.id,
          warrantyDraftFileId: war.id,
        },
      });

      return [inv, war] as const;
    });

    // Notify internal roles (best-effort): ADMIN, ASISTENTE, VENDEDOR
    try {
      const recipients = await this.prisma.user.findMany({
        where: { blocked: false, role: { in: [Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR] } },
        select: { id: true },
      });

      const payload = {
        template: 'service_closing_pending_approval' as const,
        data: {
          serviceId: service.id,
          serviceTitle: service.title,
          customerName: service.customer?.nombre ?? 'Cliente',
        },
      };

      for (const u of recipients) {
        void this.notifications.enqueueWhatsAppToUser({
          recipientUserId: u.id,
          payload,
          dedupeKey: `service_closing_pending_approval:${service.id}:${u.id}`,
        });
      }

      await this.prisma.serviceUpdate.create({
        data: {
          serviceId: service.id,
          changedByUserId: params.triggeredByUserId,
          type: ServiceUpdateType.NOTE,
          message: 'Factura y garantía generadas. Pendiente de aprobación.',
          oldValue: Prisma.DbNull,
          newValue: {
            closingId: closing.id,
            invoiceDraftFileId: invFile.id,
            warrantyDraftFileId: warFile.id,
          } as unknown as Prisma.InputJsonValue,
        },
      });
    } catch {
      // ignore
    }

    return { ...closing, invoiceDraftFileId: invFile.id, warrantyDraftFileId: warFile.id };
  }

  async getClosing(user: AuthUser, serviceId: string) {
    await this.getServiceOrThrow(user, serviceId, 'view');

    try {
      const row = await this.prisma.serviceClosing.findUnique({
        where: { serviceId },
        include: {
          invoiceDraftFile: true,
          warrantyDraftFile: true,
          invoiceApprovedFile: true,
          warrantyApprovedFile: true,
          invoiceFinalFile: true,
          warrantyFinalFile: true,
          signatureFile: true,
          approvedBy: { select: { id: true, nombreCompleto: true } },
          rejectedBy: { select: { id: true, nombreCompleto: true } },
        },
      });
      if (!row) return null;
      return row;
    } catch (e) {
      if (this.isSchemaMismatch(e)) return null;
      throw e;
    }
  }

  async updateDraft(user: AuthUser, serviceId: string, params: { invoiceData?: any; warrantyData?: any }) {
    this.assertAdminApproval(user);
    await this.getServiceOrThrow(user, serviceId, 'operate');

    try {
      const updated = await this.prisma.serviceClosing.update({
        where: { serviceId },
        data: {
          ...(params.invoiceData !== undefined
            ? { invoiceData: params.invoiceData as Prisma.InputJsonValue }
            : {}),
          ...(params.warrantyData !== undefined
            ? { warrantyData: params.warrantyData as Prisma.InputJsonValue }
            : {}),
        },
      });
      return updated;
    } catch (e) {
      if (this.isSchemaMismatch(e)) {
        throw new ServiceUnavailableException('Cierre de servicio no disponible: falta aplicar migraciones.');
      }
      throw e;
    }
  }

  async approve(user: AuthUser, serviceId: string) {
    this.assertAdminApproval(user);
    await this.getServiceOrThrow(user, serviceId, 'operate');

    const closing = await this.prisma.serviceClosing.findUnique({ where: { serviceId } });
    if (!closing) throw new NotFoundException('Workflow de cierre no existe');
    if (closing.approvalStatus === ServiceClosingApprovalStatus.APPROVED) return closing;

    const approver = await this.prisma.user.findUnique({ where: { id: user.id }, select: { nombreCompleto: true } });

    // Regenerate PDFs as "approved" (adds approval record, no signature).
    const company = await this.resolveCompanyInfo();
    const invoiceData = (closing.invoiceData ?? {}) as any;
    const warrantyData = (closing.warrantyData ?? {}) as any;
    const approvalRecord = { approvedByName: approver?.nombreCompleto ?? null, approvedAtIso: new Date().toISOString() };

    const invoicePdf = await buildInvoicePdf({
      ...(invoiceData as InvoiceDraftData),
      company: invoiceData.company ?? company,
      approvalRecord,
      signature: null,
    });

    const warrantyPdf = await buildWarrantyPdf({
      ...(warrantyData as WarrantyDraftData),
      company: warrantyData.company ?? { name: company.name },
      approvalRecord,
      signature: null,
    });

    const [invUpload, warUpload] = await Promise.all([
      this.uploadPdfToR2({
        serviceId,
        fileName: `factura_aprobada_${serviceId}.pdf`,
        pdfBytes: invoicePdf,
      }),
      this.uploadPdfToR2({
        serviceId,
        fileName: `garantia_aprobada_${serviceId}.pdf`,
        pdfBytes: warrantyPdf,
      }),
    ]);

    const service = await this.prisma.service.findUnique({
      where: { id: serviceId },
      select: { technicianId: true, title: true },
    });

    const [inv, war, updated] = await this.prisma.$transaction(async (tx) => {
      const invFile = await this.createServiceFileRowForUploadedPdf(tx, {
        serviceId,
        uploadedByUserId: user.id,
        kind: 'service_invoice_approved',
        caption: 'Factura (aprobada)',
        upload: invUpload,
      });

      const warFile = await this.createServiceFileRowForUploadedPdf(tx, {
        serviceId,
        uploadedByUserId: user.id,
        kind: 'service_warranty_approved',
        caption: 'Carta de garantía (aprobada)',
        upload: warUpload,
      });

      const row = await tx.serviceClosing.update({
        where: { serviceId },
        data: {
          approvalStatus: ServiceClosingApprovalStatus.APPROVED,
          approvedByUserId: user.id,
          approvedAt: new Date(),
          invoiceApprovedFileId: invFile.id,
          warrantyApprovedFileId: warFile.id,
          sentToTechnicianAt: new Date(),
        },
      });

      return [invFile, warFile, row] as const;
    });

    // Notify technician (best-effort)
    if (service?.technicianId) {
      const payload = {
        template: 'service_closing_approved' as const,
        data: {
          serviceId,
          serviceTitle: service?.title ?? 'Servicio',
          approvedByName: approver?.nombreCompleto ?? null,
        },
      };

      void this.notifications.enqueueWhatsAppToUser({
        recipientUserId: service.technicianId,
        payload,
        dedupeKey: `service_closing_approved:${serviceId}:${service.technicianId}:${updated.approvedAt?.toISOString?.() ?? ''}`,
      });

      // Also send links (reliable text) so technician can open.
      const tech = await this.prisma.user.findUnique({
        where: { id: service.technicianId },
        select: { id: true },
      });
      if (tech?.id) {
        const linksText = `Docs aprobados (abrir):\nFactura: ${inv.fileUrl}\nGarantía: ${war.fileUrl}`;
        void this.notifications.enqueueWhatsAppToUser({
          recipientUserId: tech.id,
          payload: {
            template: 'service_closing_ready_for_signature' as const,
            data: { serviceId, serviceTitle: service?.title ?? 'Servicio' },
          },
          dedupeKey: `service_closing_ready_for_signature:${serviceId}:${tech.id}`,
        });
        // Add a second plain message via outbox using existing template system is not supported.
        // We intentionally keep this as a service update for in-system visibility.
        await this.prisma.serviceUpdate.create({
          data: {
            serviceId,
            changedByUserId: user.id,
            type: ServiceUpdateType.NOTE,
            message: linksText,
            oldValue: Prisma.DbNull,
            newValue: { invoiceApprovedFileId: inv.id, warrantyApprovedFileId: war.id } as any,
          },
        });
      }
    }

    return updated;
  }

  async reject(user: AuthUser, serviceId: string, reason?: string | null) {
    this.assertAdminApproval(user);
    await this.getServiceOrThrow(user, serviceId, 'operate');

    const closing = await this.prisma.serviceClosing.findUnique({ where: { serviceId } });
    if (!closing) throw new NotFoundException('Workflow de cierre no existe');

    const rejectReason = (reason ?? '').toString().trim() || null;

    const updated = await this.prisma.serviceClosing.update({
      where: { serviceId },
      data: {
        approvalStatus: ServiceClosingApprovalStatus.REJECTED,
        rejectedByUserId: user.id,
        rejectedAt: new Date(),
        rejectReason,
      },
    });

    const service = await this.prisma.service.findUnique({ where: { id: serviceId }, select: { technicianId: true, title: true } });
    const rejector = await this.prisma.user.findUnique({ where: { id: user.id }, select: { nombreCompleto: true } });

    if (service?.technicianId) {
      void this.notifications.enqueueWhatsAppToUser({
        recipientUserId: service.technicianId,
        payload: {
          template: 'service_closing_rejected' as const,
          data: {
            serviceId,
            serviceTitle: service.title ?? 'Servicio',
            rejectedByName: rejector?.nombreCompleto ?? null,
            reason: rejectReason,
          },
        },
        dedupeKey: `service_closing_rejected:${serviceId}:${service.technicianId}:${updated.rejectedAt?.toISOString?.() ?? ''}`,
      });
    }

    return updated;
  }

  async finalizeAndSendToClient(user: AuthUser, serviceId: string, params: { skipSignature?: boolean }) {
    await this.getServiceOrThrow(user, serviceId, 'operate');

    const closing = await this.prisma.serviceClosing.findUnique({ where: { serviceId } });
    if (!closing) throw new NotFoundException('Workflow de cierre no existe');
    if (closing.approvalStatus !== ServiceClosingApprovalStatus.APPROVED) {
      throw new BadRequestException('Primero debe aprobarse la factura/garantía');
    }

    const service = await this.prisma.service.findUnique({
      where: { id: serviceId },
      include: { customer: true, technician: { select: { nombreCompleto: true } } },
    });
    if (!service) throw new NotFoundException('Servicio no encontrado');

    const company = await this.resolveCompanyInfo();
    const invoiceData = (closing.invoiceData ?? {}) as any;
    const warrantyData = (closing.warrantyData ?? {}) as any;

    const approver = closing.approvedByUserId
      ? await this.prisma.user.findUnique({ where: { id: closing.approvedByUserId }, select: { nombreCompleto: true } })
      : null;

    const approvalRecord = {
      approvedByName: approver?.nombreCompleto ?? null,
      approvedAtIso: closing.approvedAt?.toISOString?.() ?? null,
    };

    // Signature (optional)
    const sigRef = await this.getSignatureFileFromExecutionReport(serviceId);
    const sigBytes = sigRef?.fileId ? await this.downloadServiceFileBytes(sigRef.fileId) : null;
    const shouldEmbedSig = !!sigBytes;

    const signatureStatus = shouldEmbedSig
      ? ServiceClosingSignatureStatus.SIGNED
      : params.skipSignature
        ? ServiceClosingSignatureStatus.SKIPPED
        : ServiceClosingSignatureStatus.PENDING;

    const invoicePdf = await buildInvoicePdf({
      ...(invoiceData as InvoiceDraftData),
      company: invoiceData.company ?? company,
      approvalRecord,
      signature: shouldEmbedSig && sigBytes ? { pngBytes: sigBytes, signedAtIso: sigRef?.signedAtIso ?? null } : null,
    });

    const warrantyPdf = await buildWarrantyPdf({
      ...(warrantyData as WarrantyDraftData),
      company: warrantyData.company ?? { name: company.name },
      approvalRecord,
      signature: shouldEmbedSig && sigBytes ? { pngBytes: sigBytes, signedAtIso: sigRef?.signedAtIso ?? null } : null,
    });

    const [invUpload, warUpload] = await Promise.all([
      this.uploadPdfToR2({
        serviceId,
        fileName: `factura_final_${serviceId}.pdf`,
        pdfBytes: invoicePdf,
      }),
      this.uploadPdfToR2({
        serviceId,
        fileName: `garantia_final_${serviceId}.pdf`,
        pdfBytes: warrantyPdf,
      }),
    ]);

    const [inv, war, updated] = await this.prisma.$transaction(async (tx) => {
      const invFile = await this.createServiceFileRowForUploadedPdf(tx, {
        serviceId,
        uploadedByUserId: user.id,
        kind: 'service_invoice_final',
        caption: 'Factura (final)',
        upload: invUpload,
      });

      const warFile = await this.createServiceFileRowForUploadedPdf(tx, {
        serviceId,
        uploadedByUserId: user.id,
        kind: 'service_warranty_final',
        caption: 'Carta de garantía (final)',
        upload: warUpload,
      });

      const row = await tx.serviceClosing.update({
        where: { serviceId },
        data: {
          signatureStatus,
          signatureFileId: shouldEmbedSig ? sigRef?.fileId ?? null : null,
          signedAt: shouldEmbedSig ? new Date(sigRef?.signedAtIso ?? Date.now()) : null,
          invoiceFinalFileId: invFile.id,
          warrantyFinalFileId: warFile.id,
          sentToClientAt: new Date(),
        },
      });

      return [invFile, warFile, row] as const;
    });

    // Send to client via WhatsApp (best-effort): we enqueue text messages through outbox.
    try {
      const clientPhone = (service.customer?.telefono ?? '').trim();
      if (clientPhone) {
        const text =
          'Hola, gracias por confiar en FULLTECH.\n\nLe compartimos la factura y la carta de garantía de su servicio realizado.\nCualquier duda estamos a su disposición.\n\n' +
          `Factura: ${inv.fileUrl}\nGarantía: ${war.fileUrl}`;

        await this.notifications.enqueueWhatsAppRawText({
          toNumber: clientPhone,
          messageText: text,
          dedupeKey: `service_closing_client_docs:${serviceId}:${updated.sentToClientAt?.toISOString?.() ?? ''}`,
          payload: {
            serviceId,
            invoiceFinalFileId: inv.id,
            warrantyFinalFileId: war.id,
          },
        });

        await this.prisma.serviceUpdate.create({
          data: {
            serviceId,
            changedByUserId: user.id,
            type: ServiceUpdateType.NOTE,
            message: `WhatsApp en cola para cliente (${clientPhone}).`,
            oldValue: Prisma.DbNull,
            newValue: { invoiceFinalFileId: inv.id, warrantyFinalFileId: war.id } as any,
          },
        });

        const recipients = await this.prisma.user.findMany({
          where: { blocked: false, role: { in: [Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR] } },
          select: { id: true },
        });

        for (const u of recipients) {
          void this.notifications.enqueueWhatsAppToUser({
            recipientUserId: u.id,
            payload: { template: 'service_closing_sent_to_client' as const, data: { serviceId, serviceTitle: service.title } },
            dedupeKey: `service_closing_sent_to_client:${serviceId}:${u.id}:${updated.sentToClientAt?.toISOString?.() ?? ''}`,
          });
        }
      }
    } catch {
      // ignore
    }

    return { closing: updated, invoiceFinal: inv, warrantyFinal: war };
  }

  async assertFinalizedAndStartIfNeeded(serviceId: string, triggeredByUserId: string) {
    const service = await this.prisma.service.findFirst({ where: { id: serviceId, isDeleted: false } });
    if (!service) return;

    const isFinalized =
      service.status === ServiceStatus.COMPLETED ||
      service.status === ServiceStatus.CLOSED ||
      (service as any).orderState === 'FINALIZED';

    if (!isFinalized) return;

    return this.tryStartOnServiceFinalized({ serviceId, triggeredByUserId });
  }
}
