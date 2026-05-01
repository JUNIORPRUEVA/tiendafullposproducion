import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import {
  EmployeeWarningStatus,
  EmployeeWarningSignatureType,
  Prisma,
  Role,
} from '@prisma/client';
// eslint-disable-next-line @typescript-eslint/no-require-imports
const PDFDocument = require('pdfkit') as typeof import('pdfkit');
import { PrismaService } from '../prisma/prisma.service';
import { R2Service } from '../storage/r2.service';
import {
  AnnulEmployeeWarningDto,
  CreateEmployeeWarningDto,
  EmployeeWarningsQueryDto,
  RefuseEmployeeWarningDto,
  SignEmployeeWarningDto,
  UpdateEmployeeWarningDto,
} from './dto/employee-warning.dto';

const WARNING_INCLUDE = {
  employeeUser: {
    select: {
      id: true,
      nombreCompleto: true,
      email: true,
      cedula: true,
      workContractJobTitle: true,
    },
  },
  createdByUser: {
    select: { id: true, nombreCompleto: true },
  },
  annulledByUser: {
    select: { id: true, nombreCompleto: true },
  },
  evidences: {
    orderBy: { createdAt: 'asc' as const },
  },
  signatures: {
    orderBy: { createdAt: 'asc' as const },
  },
  auditLogs: {
    orderBy: { createdAt: 'asc' as const },
    include: {
      actorUser: { select: { id: true, nombreCompleto: true } },
    },
  },
};

const EDITABLE_STATUSES: EmployeeWarningStatus[] = [EmployeeWarningStatus.DRAFT];

@Injectable()
export class EmployeeWarningsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly r2: R2Service,
  ) {}

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  private getCompanyId(): string {
    // Single-tenant: derive from settings or env. We use a fixed approach
    // consistent with other modules – the company_id in the DB is the same
    // for all records since this is a single-company SaaS.
    return process.env.COMPANY_ID ?? '00000000-0000-0000-0000-000000000001';
  }

  private async ensureWarningExists(id: string, companyId: string) {
    const w = await this.prisma.employeeWarning.findFirst({
      where: { id, companyId },
      include: WARNING_INCLUDE,
    });
    if (!w) throw new NotFoundException('Amonestación no encontrada');
    return w;
  }

  private async nextWarningNumber(companyId: string): Promise<string> {
    const count = await this.prisma.employeeWarning.count({ where: { companyId } });
    const year = new Date().getFullYear();
    return `AMON-${year}-${String(count + 1).padStart(4, '0')}`;
  }

  private async logAudit(params: {
    warningId: string;
    action: string;
    actorUserId: string | null;
    oldStatus?: EmployeeWarningStatus | null;
    newStatus?: EmployeeWarningStatus | null;
    metadata?: Record<string, unknown>;
  }) {
    await this.prisma.employeeWarningAuditLog.create({
      data: {
        warningId: params.warningId,
        action: params.action,
        actorUserId: params.actorUserId,
        oldStatus: params.oldStatus ?? undefined,
        newStatus: params.newStatus ?? undefined,
        metadataJson: params.metadata ? (params.metadata as any) : undefined,
      },
    });
  }

  // ─── Admin: list ─────────────────────────────────────────────────────────────

  async findAll(query: EmployeeWarningsQueryDto) {
    const companyId = this.getCompanyId();
    const page = Math.max(1, parseInt(query.page ?? '1', 10));
    const limit = Math.min(100, Math.max(1, parseInt(query.limit ?? '20', 10)));
    const skip = (page - 1) * limit;

    const where: Prisma.EmployeeWarningWhereInput = { companyId };

    if (query.employeeUserId) where.employeeUserId = query.employeeUserId;

    if (query.status) {
      const st = query.status.toUpperCase().replace('-', '_') as EmployeeWarningStatus;
      if (Object.values(EmployeeWarningStatus).includes(st)) {
        where.status = st;
      }
    }

    if (query.severity) {
      const sev = query.severity.toUpperCase();
      where.severity = sev as any;
    }

    if (query.category) {
      const cat = query.category.toUpperCase();
      where.category = cat as any;
    }

    if (query.fromDate || query.toDate) {
      where.warningDate = {};
      if (query.fromDate) where.warningDate.gte = new Date(query.fromDate);
      if (query.toDate) where.warningDate.lte = new Date(query.toDate);
    }

    if (query.search) {
      const q = query.search.trim();
      where.OR = [
        { title: { contains: q, mode: 'insensitive' } },
        { warningNumber: { contains: q, mode: 'insensitive' } },
        { employeeUser: { nombreCompleto: { contains: q, mode: 'insensitive' } } },
      ];
    }

    const [items, total] = await this.prisma.$transaction([
      this.prisma.employeeWarning.findMany({
        where,
        include: WARNING_INCLUDE,
        orderBy: { createdAt: 'desc' },
        skip,
        take: limit,
      }),
      this.prisma.employeeWarning.count({ where }),
    ]);

    return { items, total, page, limit };
  }

  // ─── Admin: find one ─────────────────────────────────────────────────────────

  async findOne(id: string) {
    return this.ensureWarningExists(id, this.getCompanyId());
  }

  // ─── Admin: create ───────────────────────────────────────────────────────────

  async create(dto: CreateEmployeeWarningDto, actorId: string) {
    const companyId = this.getCompanyId();

    // Verify employee exists
    const employee = await this.prisma.user.findUnique({
      where: { id: dto.employeeUserId },
    });
    if (!employee) throw new NotFoundException('Empleado no encontrado');

    const warningNumber = await this.nextWarningNumber(companyId);

    const warning = await this.prisma.employeeWarning.create({
      data: {
        companyId,
        employeeUserId: dto.employeeUserId,
        createdByUserId: actorId,
        warningNumber,
        warningDate: new Date(dto.warningDate),
        incidentDate: new Date(dto.incidentDate),
        title: dto.title.trim(),
        category: dto.category,
        severity: dto.severity,
        legalBasis: dto.legalBasis?.trim() ?? null,
        internalRuleReference: dto.internalRuleReference?.trim() ?? null,
        description: dto.description.trim(),
        employeeExplanation: dto.employeeExplanation?.trim() ?? null,
        correctiveAction: dto.correctiveAction?.trim() ?? null,
        consequenceNote: dto.consequenceNote?.trim() ?? null,
        evidenceNotes: dto.evidenceNotes?.trim() ?? null,
        status: EmployeeWarningStatus.DRAFT,
      },
      include: WARNING_INCLUDE,
    });

    await this.logAudit({
      warningId: warning.id,
      action: 'created',
      actorUserId: actorId,
      newStatus: EmployeeWarningStatus.DRAFT,
    });

    return warning;
  }

  // ─── Admin: update (draft only) ──────────────────────────────────────────────

  async update(id: string, dto: UpdateEmployeeWarningDto, actorId: string) {
    const warning = await this.ensureWarningExists(id, this.getCompanyId());

    if (!EDITABLE_STATUSES.includes(warning.status)) {
      throw new BadRequestException(
        'Solo se pueden editar amonestaciones en estado borrador',
      );
    }

    const updated = await this.prisma.employeeWarning.update({
      where: { id },
      data: {
        ...(dto.warningDate && { warningDate: new Date(dto.warningDate) }),
        ...(dto.incidentDate && { incidentDate: new Date(dto.incidentDate) }),
        ...(dto.title && { title: dto.title.trim() }),
        ...(dto.category && { category: dto.category }),
        ...(dto.severity && { severity: dto.severity }),
        ...(dto.legalBasis !== undefined && { legalBasis: dto.legalBasis?.trim() ?? null }),
        ...(dto.internalRuleReference !== undefined && {
          internalRuleReference: dto.internalRuleReference?.trim() ?? null,
        }),
        ...(dto.description && { description: dto.description.trim() }),
        ...(dto.employeeExplanation !== undefined && {
          employeeExplanation: dto.employeeExplanation?.trim() ?? null,
        }),
        ...(dto.correctiveAction !== undefined && {
          correctiveAction: dto.correctiveAction?.trim() ?? null,
        }),
        ...(dto.consequenceNote !== undefined && {
          consequenceNote: dto.consequenceNote?.trim() ?? null,
        }),
        ...(dto.evidenceNotes !== undefined && {
          evidenceNotes: dto.evidenceNotes?.trim() ?? null,
        }),
      },
      include: WARNING_INCLUDE,
    });

    await this.logAudit({
      warningId: id,
      action: 'updated',
      actorUserId: actorId,
    });

    return updated;
  }

  // ─── Admin: delete draft ─────────────────────────────────────────────────────

  async deleteDraft(id: string, actorId: string) {
    const warning = await this.ensureWarningExists(id, this.getCompanyId());

    if (warning.status !== EmployeeWarningStatus.DRAFT) {
      throw new BadRequestException(
        'Solo se pueden eliminar amonestaciones en borrador',
      );
    }

    // Clean up evidences from R2
    for (const ev of warning.evidences) {
      if (ev.storageKey) {
        try { await this.r2.deleteObject(ev.storageKey); } catch { /* best-effort */ }
      }
    }

    await this.prisma.employeeWarning.delete({ where: { id } });

    return { deleted: true };
  }

  // ─── Admin: submit for signature ─────────────────────────────────────────────

  async submit(id: string, actorId: string) {
    const warning = await this.ensureWarningExists(id, this.getCompanyId());

    if (warning.status !== EmployeeWarningStatus.DRAFT) {
      throw new BadRequestException('Solo se pueden enviar amonestaciones en borrador');
    }

    const pdfBuffer = await this.generatePdfBuffer(warning as any);
    const objectKey = `employee-warnings/${id}/amonestacion-${warning.warningNumber}.pdf`;
    await this.r2.putObject({ objectKey, body: pdfBuffer, contentType: 'application/pdf' });
    const pdfUrl = this.r2.buildPublicUrl(objectKey);

    const updated = await this.prisma.employeeWarning.update({
      where: { id },
      data: {
        status: EmployeeWarningStatus.PENDING_SIGNATURE,
        submittedAt: new Date(),
        pdfUrl,
      },
      include: WARNING_INCLUDE,
    });

    await this.logAudit({
      warningId: id,
      action: 'submitted_for_signature',
      actorUserId: actorId,
      oldStatus: EmployeeWarningStatus.DRAFT,
      newStatus: EmployeeWarningStatus.PENDING_SIGNATURE,
    });

    return updated;
  }

  // ─── Admin: annul ─────────────────────────────────────────────────────────────

  async annul(id: string, dto: AnnulEmployeeWarningDto, actorId: string) {
    const warning = await this.ensureWarningExists(id, this.getCompanyId());

    if (
      warning.status === EmployeeWarningStatus.DRAFT ||
      warning.status === EmployeeWarningStatus.ANNULLED
    ) {
      throw new BadRequestException('Estado no permite anulación');
    }

    const oldStatus = warning.status;

    const updated = await this.prisma.employeeWarning.update({
      where: { id },
      data: {
        status: EmployeeWarningStatus.ANNULLED,
        annulledAt: new Date(),
        annulledByUserId: actorId,
        annulmentReason: dto.annulmentReason.trim(),
      },
      include: WARNING_INCLUDE,
    });

    await this.logAudit({
      warningId: id,
      action: 'annulled',
      actorUserId: actorId,
      oldStatus,
      newStatus: EmployeeWarningStatus.ANNULLED,
      metadata: { reason: dto.annulmentReason },
    });

    return updated;
  }

  // ─── Admin: regenerate PDF ────────────────────────────────────────────────────

  async generatePdf(id: string, actorId: string) {
    const warning = await this.ensureWarningExists(id, this.getCompanyId());
    const pdfBuffer = await this.generatePdfBuffer(warning as any);
    const objectKey = `employee-warnings/${id}/amonestacion-${warning.warningNumber}.pdf`;
    await this.r2.putObject({ objectKey, body: pdfBuffer, contentType: 'application/pdf' });
    const pdfUrl = this.r2.buildPublicUrl(objectKey);

    await this.prisma.employeeWarning.update({ where: { id }, data: { pdfUrl } });

    await this.logAudit({
      warningId: id,
      action: 'pdf_generated',
      actorUserId: actorId,
    });

    return { pdfUrl };
  }

  // ─── Admin: upload evidence ───────────────────────────────────────────────────

  async uploadEvidence(
    id: string,
    file: { buffer: Buffer; originalname: string; mimetype: string },
    actorId: string,
  ) {
    const warning = await this.ensureWarningExists(id, this.getCompanyId());

    if (!EDITABLE_STATUSES.includes(warning.status)) {
      throw new BadRequestException(
        'Solo se pueden subir evidencias a amonestaciones en borrador',
      );
    }

    const ext = file.originalname.split('.').pop() ?? 'bin';
    const objectKey = `employee-warnings/${id}/evidences/${Date.now()}.${ext}`;
    await this.r2.putObject({
      objectKey,
      body: file.buffer,
      contentType: file.mimetype,
    });
    const fileUrl = this.r2.buildPublicUrl(objectKey);

    const evidence = await this.prisma.employeeWarningEvidence.create({
      data: {
        warningId: id,
        fileUrl,
        fileName: file.originalname,
        fileType: file.mimetype,
        storageKey: objectKey,
        uploadedByUserId: actorId,
      },
    });

    await this.logAudit({
      warningId: id,
      action: 'evidence_uploaded',
      actorUserId: actorId,
      metadata: { fileName: file.originalname },
    });

    return evidence;
  }

  // ─── Employee: my pending ─────────────────────────────────────────────────────

  async findMyPending(userId: string) {
    const companyId = this.getCompanyId();
    const items = await this.prisma.employeeWarning.findMany({
      where: {
        companyId,
        employeeUserId: userId,
        status: EmployeeWarningStatus.PENDING_SIGNATURE,
      },
      include: WARNING_INCLUDE,
      orderBy: { submittedAt: 'desc' },
    });
    return items;
  }

  // ─── Employee: get own warning ────────────────────────────────────────────────

  async findMyWarning(id: string, userId: string) {
    const companyId = this.getCompanyId();
    const warning = await this.prisma.employeeWarning.findFirst({
      where: { id, companyId, employeeUserId: userId },
      include: WARNING_INCLUDE,
    });
    if (!warning) throw new NotFoundException('Amonestación no encontrada');
    return warning;
  }

  // ─── Employee: sign ───────────────────────────────────────────────────────────

  async sign(id: string, dto: SignEmployeeWarningDto, userId: string, ipAddress: string) {
    const companyId = this.getCompanyId();
    const warning = await this.prisma.employeeWarning.findFirst({
      where: { id, companyId, employeeUserId: userId },
      include: WARNING_INCLUDE,
    });

    if (!warning) throw new NotFoundException('Amonestación no encontrada');

    if (warning.status !== EmployeeWarningStatus.PENDING_SIGNATURE) {
      throw new BadRequestException('La amonestación no está pendiente de firma');
    }

    const existingSig = warning.signatures.find((s) => s.employeeUserId === userId);
    if (existingSig) throw new BadRequestException('Ya registraste una firma en esta amonestación');

    const now = new Date();

    await this.prisma.$transaction(async (tx) => {
      await tx.employeeWarningSignature.create({
        data: {
          warningId: id,
          employeeUserId: userId,
          signatureType: EmployeeWarningSignatureType.SIGNED,
          signatureImageUrl: dto.signatureImageUrl ?? null,
          typedName: dto.typedName.trim(),
          comment: dto.comment?.trim() ?? null,
          ipAddress: ipAddress ?? null,
          deviceInfo: dto.deviceInfo?.trim() ?? null,
          signedAt: now,
        },
      });

      await tx.employeeWarning.update({
        where: { id },
        data: {
          status: EmployeeWarningStatus.SIGNED,
          signedAt: now,
        },
      });
    });

    await this.logAudit({
      warningId: id,
      action: 'signed',
      actorUserId: userId,
      oldStatus: EmployeeWarningStatus.PENDING_SIGNATURE,
      newStatus: EmployeeWarningStatus.SIGNED,
      metadata: { typedName: dto.typedName },
    });

    // Generate signed PDF
    try {
      const updated = await this.prisma.employeeWarning.findUnique({
        where: { id },
        include: WARNING_INCLUDE,
      });
      const pdfBuffer = await this.generatePdfBuffer(updated as any, true);
      const objectKey = `employee-warnings/${id}/amonestacion-${warning.warningNumber}-firmada.pdf`;
      await this.r2.putObject({ objectKey, body: pdfBuffer, contentType: 'application/pdf' });
      const signedPdfUrl = this.r2.buildPublicUrl(objectKey);
      await this.prisma.employeeWarning.update({ where: { id }, data: { signedPdfUrl } });
    } catch (e) {
      // best-effort PDF generation after signing
      console.error('[EmployeeWarnings] Error generando PDF firmado:', e);
    }

    return this.prisma.employeeWarning.findUnique({ where: { id }, include: WARNING_INCLUDE });
  }

  // ─── Employee: refuse ─────────────────────────────────────────────────────────

  async refuse(id: string, dto: RefuseEmployeeWarningDto, userId: string, ipAddress: string) {
    const companyId = this.getCompanyId();
    const warning = await this.prisma.employeeWarning.findFirst({
      where: { id, companyId, employeeUserId: userId },
      include: WARNING_INCLUDE,
    });

    if (!warning) throw new NotFoundException('Amonestación no encontrada');

    if (warning.status !== EmployeeWarningStatus.PENDING_SIGNATURE) {
      throw new BadRequestException('La amonestación no está pendiente de firma');
    }

    const existingSig = warning.signatures.find((s) => s.employeeUserId === userId);
    if (existingSig) throw new BadRequestException('Ya registraste una firma en esta amonestación');

    const now = new Date();

    await this.prisma.$transaction(async (tx) => {
      await tx.employeeWarningSignature.create({
        data: {
          warningId: id,
          employeeUserId: userId,
          signatureType: EmployeeWarningSignatureType.REFUSED,
          signatureImageUrl: null,
          typedName: dto.typedName.trim(),
          comment: dto.comment.trim(),
          ipAddress: ipAddress ?? null,
          deviceInfo: dto.deviceInfo?.trim() ?? null,
          signedAt: now,
        },
      });

      await tx.employeeWarning.update({
        where: { id },
        data: {
          status: EmployeeWarningStatus.REFUSED_TO_SIGN,
          refusedAt: now,
        },
      });
    });

    await this.logAudit({
      warningId: id,
      action: 'refused_to_sign',
      actorUserId: userId,
      oldStatus: EmployeeWarningStatus.PENDING_SIGNATURE,
      newStatus: EmployeeWarningStatus.REFUSED_TO_SIGN,
      metadata: { comment: dto.comment },
    });

    // Generate refusal PDF
    try {
      const updated = await this.prisma.employeeWarning.findUnique({
        where: { id },
        include: WARNING_INCLUDE,
      });
      const pdfBuffer = await this.generatePdfBuffer(updated as any, true);
      const objectKey = `employee-warnings/${id}/amonestacion-${warning.warningNumber}-negativa.pdf`;
      await this.r2.putObject({ objectKey, body: pdfBuffer, contentType: 'application/pdf' });
      const signedPdfUrl = this.r2.buildPublicUrl(objectKey);
      await this.prisma.employeeWarning.update({ where: { id }, data: { signedPdfUrl } });
    } catch (e) {
      console.error('[EmployeeWarnings] Error generando PDF de negativa:', e);
    }

    return this.prisma.employeeWarning.findUnique({ where: { id }, include: WARNING_INCLUDE });
  }

  // ─── Employee: stream PDF ─────────────────────────────────────────────────────

  async getMyPdfBytes(
    id: string,
    userId: string,
  ): Promise<{ body: Buffer; contentType: string; filename: string }> {
    const companyId = this.getCompanyId();
    const warning = await this.prisma.employeeWarning.findFirst({
      where: { id, companyId, employeeUserId: userId },
      select: { id: true, pdfUrl: true, warningNumber: true },
    });

    if (!warning) throw new NotFoundException('Amonestación no encontrada');
    if (!warning.pdfUrl) {
      throw new NotFoundException(
        'El PDF de esta amonestación aún no está disponible. Contacta a Recursos Humanos.',
      );
    }

    // Derive the R2 object key.
    // When R2_PUBLIC_BASE_URL is not configured, buildPublicUrl returns the raw
    // object key (no scheme). When it IS configured it returns a full https URL.
    let objectKey: string;
    try {
      const url = new URL(warning.pdfUrl);
      // It's a full URL — extract the path without leading slash as the key.
      objectKey = url.pathname.replace(/^\//, '');
    } catch {
      // Not a valid absolute URL → it's already the raw object key.
      objectKey = warning.pdfUrl;
    }

    const { body, contentType } = await this.r2.getObject(objectKey);
    const filename = `amonestacion-${warning.warningNumber}.pdf`;
    return { body, contentType: contentType ?? 'application/pdf', filename };
  }

  // ─── PDF generation ───────────────────────────────────────────────────────────

  private async generatePdfBuffer(warning: any, withSignature = false): Promise<Buffer> {
    return new Promise((resolve, reject) => {
      const chunks: Buffer[] = [];
      const doc = new PDFDocument({ margin: 60, size: 'LETTER' });

      doc.on('data', (chunk: Buffer) => chunks.push(chunk));
      doc.on('end', () => resolve(Buffer.concat(chunks)));
      doc.on('error', reject);

      const scheme = { primary: '#1a1a2e', accent: '#e63946', muted: '#555555' };

      const categoryLabels: Record<string, string> = {
        TARDINESS: 'Tardanza',
        ABSENCE: 'Ausencia',
        MISCONDUCT: 'Conducta inapropiada',
        NEGLIGENCE: 'Negligencia',
        POLICY_VIOLATION: 'Violación de política',
        INSUBORDINATION: 'Insubordinación',
        OTHER: 'Otro',
      };

      const severityLabels: Record<string, string> = {
        LOW: 'Leve',
        MEDIUM: 'Moderada',
        HIGH: 'Grave',
        CRITICAL: 'Muy Grave',
      };

      const statusLabels: Record<string, string> = {
        DRAFT: 'Borrador',
        PENDING_SIGNATURE: 'Pendiente de firma',
        SIGNED: 'Firmada',
        REFUSED_TO_SIGN: 'Negativa a firmar',
        ANNULLED: 'Anulada',
        ARCHIVED: 'Archivada',
      };

      const fmt = (d: Date | null | undefined) =>
        d ? new Intl.DateTimeFormat('es-DO', { dateStyle: 'long' }).format(new Date(d)) : '—';

      // ── Header ──
      doc
        .fillColor(scheme.primary)
        .fontSize(16)
        .font('Helvetica-Bold')
        .text('AMONESTACIÓN LABORAL', { align: 'center' });
      doc.moveDown(0.3);
      doc
        .fillColor(scheme.muted)
        .fontSize(10)
        .font('Helvetica')
        .text('República Dominicana — Documento de Recursos Humanos', { align: 'center' });
      doc.moveDown(0.5);
      doc
        .moveTo(60, doc.y)
        .lineTo(552, doc.y)
        .strokeColor(scheme.accent)
        .lineWidth(2)
        .stroke();
      doc.moveDown(0.8);

      // ── Meta row ──
      const row = (label: string, value: string) => {
        doc
          .fillColor(scheme.muted)
          .fontSize(9)
          .font('Helvetica-Bold')
          .text(`${label.toUpperCase()}: `, { continued: true })
          .fillColor(scheme.primary)
          .font('Helvetica')
          .text(value || '—');
      };

      row('No. Amonestación', warning.warningNumber);
      row('Fecha del documento', fmt(warning.warningDate));
      row('Fecha del incidente', fmt(warning.incidentDate));
      row('Estado', statusLabels[warning.status] ?? warning.status);
      doc.moveDown(0.6);

      // ── Employee info ──
      doc
        .fillColor(scheme.primary)
        .fontSize(11)
        .font('Helvetica-Bold')
        .text('DATOS DEL EMPLEADO');
      doc.moveTo(60, doc.y).lineTo(552, doc.y).strokeColor('#cccccc').lineWidth(0.5).stroke();
      doc.moveDown(0.4);
      row('Nombre completo', warning.employeeUser?.nombreCompleto ?? '—');
      if (warning.employeeUser?.cedula) row('Cédula', warning.employeeUser.cedula);
      if (warning.employeeUser?.workContractJobTitle)
        row('Cargo', warning.employeeUser.workContractJobTitle);
      doc.moveDown(0.6);

      // ── Warning details ──
      doc.fillColor(scheme.primary).fontSize(11).font('Helvetica-Bold').text('DETALLES');
      doc.moveTo(60, doc.y).lineTo(552, doc.y).strokeColor('#cccccc').lineWidth(0.5).stroke();
      doc.moveDown(0.4);
      row('Título', warning.title);
      row('Categoría', categoryLabels[warning.category] ?? warning.category);
      row('Severidad', severityLabels[warning.severity] ?? warning.severity);
      if (warning.legalBasis) row('Base legal', warning.legalBasis);
      if (warning.internalRuleReference)
        row('Referencia reglamento interno', warning.internalRuleReference);
      doc.moveDown(0.6);

      // ── Description ──
      doc.fillColor(scheme.primary).fontSize(11).font('Helvetica-Bold').text('DESCRIPCIÓN DE LOS HECHOS');
      doc.moveTo(60, doc.y).lineTo(552, doc.y).strokeColor('#cccccc').lineWidth(0.5).stroke();
      doc.moveDown(0.4);
      doc.fillColor(scheme.muted).fontSize(10).font('Helvetica').text(warning.description, {
        width: 492,
        align: 'justify',
      });
      doc.moveDown(0.6);

      // ── Corrective action ──
      if (warning.correctiveAction) {
        doc
          .fillColor(scheme.primary)
          .fontSize(11)
          .font('Helvetica-Bold')
          .text('ACCIÓN CORRECTIVA REQUERIDA');
        doc.moveTo(60, doc.y).lineTo(552, doc.y).strokeColor('#cccccc').lineWidth(0.5).stroke();
        doc.moveDown(0.4);
        doc
          .fillColor(scheme.muted)
          .fontSize(10)
          .font('Helvetica')
          .text(warning.correctiveAction, { width: 492, align: 'justify' });
        doc.moveDown(0.6);
      }

      // ── Consequence note ──
      if (warning.consequenceNote) {
        doc
          .fillColor(scheme.primary)
          .fontSize(11)
          .font('Helvetica-Bold')
          .text('CONSECUENCIAS');
        doc.moveTo(60, doc.y).lineTo(552, doc.y).strokeColor('#cccccc').lineWidth(0.5).stroke();
        doc.moveDown(0.4);
        doc
          .fillColor(scheme.muted)
          .fontSize(10)
          .font('Helvetica')
          .text(warning.consequenceNote, { width: 492, align: 'justify' });
        doc.moveDown(0.6);
      }

      // ── Employee explanation ──
      if (warning.employeeExplanation) {
        doc
          .fillColor(scheme.primary)
          .fontSize(11)
          .font('Helvetica-Bold')
          .text('DESCARGO DEL EMPLEADO');
        doc.moveTo(60, doc.y).lineTo(552, doc.y).strokeColor('#cccccc').lineWidth(0.5).stroke();
        doc.moveDown(0.4);
        doc
          .fillColor(scheme.muted)
          .fontSize(10)
          .font('Helvetica')
          .text(warning.employeeExplanation, { width: 492, align: 'justify' });
        doc.moveDown(0.6);
      }

      // ── Evidences ──
      if (warning.evidences?.length) {
        doc
          .fillColor(scheme.primary)
          .fontSize(11)
          .font('Helvetica-Bold')
          .text('EVIDENCIAS ADJUNTAS');
        doc.moveTo(60, doc.y).lineTo(552, doc.y).strokeColor('#cccccc').lineWidth(0.5).stroke();
        doc.moveDown(0.4);
        for (const ev of warning.evidences) {
          doc
            .fillColor(scheme.muted)
            .fontSize(9)
            .font('Helvetica')
            .text(`• ${ev.fileName}`, { width: 492 });
        }
        doc.moveDown(0.6);
      }

      // ── Issuer ──
      doc
        .fillColor(scheme.primary)
        .fontSize(11)
        .font('Helvetica-Bold')
        .text('EMITIDA POR');
      doc.moveTo(60, doc.y).lineTo(552, doc.y).strokeColor('#cccccc').lineWidth(0.5).stroke();
      doc.moveDown(0.4);
      row('Responsable RRHH / Admin', warning.createdByUser?.nombreCompleto ?? '—');
      doc.moveDown(1.2);

      // ── Signature section ──
      if (withSignature && warning.signatures?.length) {
        const sig = warning.signatures[0];
        doc
          .fillColor(scheme.primary)
          .fontSize(11)
          .font('Helvetica-Bold')
          .text(
            sig.signatureType === 'REFUSED'
              ? 'NEGATIVA A FIRMAR'
              : 'RECEPCIÓN / FIRMA DEL EMPLEADO',
          );
        doc.moveTo(60, doc.y).lineTo(552, doc.y).strokeColor('#cccccc').lineWidth(0.5).stroke();
        doc.moveDown(0.4);
        row('Empleado', warning.employeeUser?.nombreCompleto ?? '—');
        row(
          sig.signatureType === 'REFUSED' ? 'Se negó a firmar el' : 'Firmado el',
          fmt(sig.signedAt),
        );
        row('Nombre escrito', sig.typedName);
        if (sig.comment) row('Comentario / motivo', sig.comment);
        if (sig.ipAddress) row('IP registrada', sig.ipAddress);
      } else {
        doc
          .fillColor(scheme.primary)
          .fontSize(11)
          .font('Helvetica-Bold')
          .text('FIRMA DEL EMPLEADO (PENDIENTE)');
        doc.moveTo(60, doc.y).lineTo(552, doc.y).strokeColor('#cccccc').lineWidth(0.5).stroke();
        doc.moveDown(2);
        doc
          .moveTo(60, doc.y)
          .lineTo(252, doc.y)
          .strokeColor('#333333')
          .lineWidth(1)
          .stroke();
        doc.moveDown(0.2);
        doc.fillColor(scheme.muted).fontSize(9).text('Firma del empleado', 60);
      }

      // ── Annulment ──
      if (warning.status === 'ANNULLED') {
        doc.moveDown(0.8);
        doc
          .fillColor(scheme.accent)
          .fontSize(11)
          .font('Helvetica-Bold')
          .text('ANULADA');
        doc.moveTo(60, doc.y).lineTo(552, doc.y).strokeColor(scheme.accent).lineWidth(0.5).stroke();
        doc.moveDown(0.4);
        doc
          .fillColor(scheme.muted)
          .fontSize(9)
          .font('Helvetica')
          .text(`Anulada el ${fmt(warning.annulledAt)} por ${warning.annulledByUser?.nombreCompleto ?? '—'}.`);
        doc.text(`Motivo: ${warning.annulmentReason ?? '—'}`);
      }

      // ── Footer ──
      doc.moveDown(1.5);
      doc
        .moveTo(60, doc.y)
        .lineTo(552, doc.y)
        .strokeColor('#cccccc')
        .lineWidth(0.5)
        .stroke();
      doc.moveDown(0.3);
      doc
        .fillColor(scheme.muted)
        .fontSize(8)
        .font('Helvetica')
        .text(
          `Documento generado el ${new Date().toLocaleString('es-DO')} · Sistema FullTech RRHH · Uso confidencial`,
          { align: 'center' },
        );

      doc.end();
    });
  }
}
