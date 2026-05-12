import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { EmployeeWarningStatus, Prisma } from '@prisma/client';
// eslint-disable-next-line @typescript-eslint/no-require-imports
const PDFDocument = require('pdfkit') as typeof import('pdfkit');
import { PrismaService } from '../prisma/prisma.service';
import { R2Service } from '../storage/r2.service';
import {
  AnnulEmployeeWarningDto,
  CreateEmployeeWarningDto,
  EmployeeWarningsQueryDto,
  UpdateEmployeeWarningDto,
} from './dto/employee-warning.dto';

const WARNING_INCLUDE = {
  employeeUser: {
    select: {
      id: true,
      nombreCompleto: true,
      email: true,
      cedula: true,
      telefono: true,
      workContractJobTitle: true,
      workContractWorkLocation: true,
    },
  },
  createdByUser: {
    select: { id: true, nombreCompleto: true, workContractJobTitle: true },
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

  private getCompanyId(): string {
    return process.env.COMPANY_ID ?? '00000000-0000-0000-0000-000000000001';
  }

  private valueOrDefault(value: string | null | undefined): string {
    const v = (value ?? '').trim();
    return v.length > 0 ? v : 'No registrado';
  }

  private cleanOptional(value: string | undefined): string | null {
    const v = (value ?? '').trim();
    return v.length > 0 ? v : null;
  }

  private safeStatus(status: string): EmployeeWarningStatus {
    const normalized = status.toUpperCase().replace('-', '_');
    if (normalized === 'ISSUED') return normalized as EmployeeWarningStatus;
    if (normalized in EmployeeWarningStatus) {
      return normalized as EmployeeWarningStatus;
    }
    return EmployeeWarningStatus.DRAFT;
  }

  private async ensureWarningExists(id: string, companyId: string) {
    const w = await this.prisma.employeeWarning.findFirst({
      where: { id, companyId },
      include: WARNING_INCLUDE,
    });
    if (!w) throw new NotFoundException('Amonestacion no encontrada');
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

  private buildGeneratedText(input: {
    warningDate: Date;
    incidentDate: Date;
    incidentTime?: string | null;
    incidentPlace?: string | null;
    reason: string;
    details: string;
    employeeName: string;
    employeeCedula: string;
    employeePosition: string;
    employeeDepartment: string;
    companyName: string;
    companyRnc: string;
    companyAddress: string;
    issuerName: string;
    issuerPosition: string;
  }): string {
    const fmtDate = (d: Date) =>
      new Intl.DateTimeFormat('es-DO', { day: '2-digit', month: '2-digit', year: 'numeric' }).format(d);

    return `AMONESTACION ESCRITA

En fecha ${fmtDate(input.warningDate)}, la empresa ${input.companyName}, RNC ${input.companyRnc}, emite la presente amonestacion al colaborador ${input.employeeName}, cedula ${input.employeeCedula}, quien ocupa el cargo de ${input.employeePosition} en el area de ${input.employeeDepartment}.

La presente amonestacion se emite por el siguiente motivo:

${input.reason}

Detalle de los hechos:

${input.details}

Los hechos ocurrieron en fecha ${fmtDate(input.incidentDate)}, aproximadamente a las ${this.valueOrDefault(input.incidentTime ?? null)}, en ${this.valueOrDefault(input.incidentPlace ?? null)}.

Se le exhorta al colaborador a corregir dicha conducta y cumplir correctamente con las normas internas de la empresa, las instrucciones de sus superiores y las obligaciones propias de su puesto.

Esta amonestacion queda registrada en el expediente laboral del colaborador como constancia formal. En caso de reincidencia o comision de nuevas faltas, la empresa podra tomar las medidas correspondientes conforme a sus politicas internas y la legislacion laboral aplicable en Republica Dominicana.

Emitido por:

${input.issuerName}
${input.issuerPosition}`;
  }

  async findAll(query: EmployeeWarningsQueryDto) {
    const companyId = this.getCompanyId();
    const page = Math.max(1, parseInt(query.page ?? '1', 10));
    const limit = Math.min(100, Math.max(1, parseInt(query.limit ?? '20', 10)));
    const skip = (page - 1) * limit;

    const where: Prisma.EmployeeWarningWhereInput = { companyId };

    if (query.employeeUserId) where.employeeUserId = query.employeeUserId;
    if (query.status) (where as any).status = this.safeStatus(query.status);
    if (query.warningType) (where as any).warningType = query.warningType.toUpperCase();

    if (query.fromDate || query.toDate) {
      where.warningDate = {};
      if (query.fromDate) where.warningDate.gte = new Date(query.fromDate);
      if (query.toDate) where.warningDate.lte = new Date(query.toDate);
    }

    if (query.search) {
      const q = query.search.trim();
      where.OR = [
        { warningNumber: { contains: q, mode: 'insensitive' } },
        { title: { contains: q, mode: 'insensitive' } },
        { description: { contains: q, mode: 'insensitive' } },
        { employeeUser: { nombreCompleto: { contains: q, mode: 'insensitive' } } },
        { createdByUser: { nombreCompleto: { contains: q, mode: 'insensitive' } } },
        { reason: { contains: q, mode: 'insensitive' } } as any,
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

  async findOne(id: string) {
    return this.ensureWarningExists(id, this.getCompanyId());
  }

  async create(dto: CreateEmployeeWarningDto, actorId: string) {
    const companyId = this.getCompanyId();

    const employee = await this.prisma.user.findUnique({ where: { id: dto.employeeUserId } });
    if (!employee) throw new NotFoundException('Empleado no encontrado');

    const issuerId = dto.issuedByUserId ?? actorId;
    const issuer = await this.prisma.user.findUnique({ where: { id: issuerId } });

    const appConfig = await this.prisma.appConfig.findUnique({
      where: { id: 'global' },
      select: { companyName: true, rnc: true, address: true },
    });

    const employeeNameSnapshot = this.valueOrDefault(employee.nombreCompleto);
    const employeeCedulaSnapshot = this.valueOrDefault(employee.cedula);
    const employeePositionSnapshot = this.valueOrDefault(employee.workContractJobTitle);
    const employeeDepartmentSnapshot = this.valueOrDefault(employee.workContractWorkLocation);
    const employeePhoneSnapshot = this.valueOrDefault(employee.telefono);

    const issuedByNameSnapshot = this.valueOrDefault(
      this.cleanOptional(dto.issuedByNameSnapshot) ?? issuer?.nombreCompleto,
    );
    const issuedByPositionSnapshot = this.valueOrDefault(
      this.cleanOptional(dto.issuedByPositionSnapshot) ?? issuer?.workContractJobTitle,
    );

    const companyNameSnapshot = this.valueOrDefault(appConfig?.companyName);
    const companyRncSnapshot = this.valueOrDefault(appConfig?.rnc);
    const companyAddressSnapshot = this.valueOrDefault(appConfig?.address);

    const warningNumber = await this.nextWarningNumber(companyId);
    const warningDate = new Date(dto.warningDate);
    const incidentDate = new Date(dto.incidentDate);
    const reason = dto.reason.trim();
    const details = dto.details.trim();

    if (!reason) throw new BadRequestException('El motivo es obligatorio');
    if (!details) throw new BadRequestException('El detalle de los hechos es obligatorio');

    const generatedText = this.buildGeneratedText({
      warningDate,
      incidentDate,
      incidentTime: dto.incidentTime,
      incidentPlace: dto.incidentPlace,
      reason,
      details,
      employeeName: employeeNameSnapshot,
      employeeCedula: employeeCedulaSnapshot,
      employeePosition: employeePositionSnapshot,
      employeeDepartment: employeeDepartmentSnapshot,
      companyName: companyNameSnapshot,
      companyRnc: companyRncSnapshot,
      companyAddress: companyAddressSnapshot,
      issuerName: issuedByNameSnapshot,
      issuerPosition: issuedByPositionSnapshot,
    });

    const status = dto.saveAsDraft ? EmployeeWarningStatus.DRAFT : ('ISSUED' as EmployeeWarningStatus);

    const warning = await this.prisma.employeeWarning.create({
      data: {
        companyId,
        employeeUserId: dto.employeeUserId,
        createdByUserId: actorId,
        warningNumber,
        warningDate,
        incidentDate,
        title: reason,
        category: 'OTHER' as any,
        severity: 'MEDIUM' as any,
        description: details,
        status,
        submittedAt: status === EmployeeWarningStatus.DRAFT ? null : new Date(),
        reason,
        details,
        warningType: dto.warningType,
        incidentTime: this.cleanOptional(dto.incidentTime),
        incidentPlace: this.cleanOptional(dto.incidentPlace),
        issuedByUserId: issuer?.id ?? null,
        issuedByNameSnapshot,
        issuedByPositionSnapshot,
        internalNotes: this.cleanOptional(dto.internalNotes),
        generatedText,
        employeeNameSnapshot,
        employeeCedulaSnapshot,
        employeePositionSnapshot,
        employeeDepartmentSnapshot,
        employeePhoneSnapshot,
        companyNameSnapshot,
        companyRncSnapshot,
        companyAddressSnapshot,
      } as any,
      include: WARNING_INCLUDE,
    });

    const pdfBuffer = await this.generatePdfBuffer(warning as any);
    const objectKey = `employee-warnings/${warning.id}/amonestacion-${warning.warningNumber}.pdf`;
    await this.r2.putObject({ objectKey, body: pdfBuffer, contentType: 'application/pdf' });
    const pdfUrl = this.r2.buildPublicUrl(objectKey);

    const updated = await this.prisma.employeeWarning.update({
      where: { id: warning.id },
      data: { pdfUrl },
      include: WARNING_INCLUDE,
    });

    await this.logAudit({
      warningId: warning.id,
      action: status === EmployeeWarningStatus.DRAFT ? 'created_draft' : 'created_issued',
      actorUserId: actorId,
      newStatus: status,
      metadata: {
        employeeUserId: dto.employeeUserId,
        warningType: dto.warningType,
        reason,
      },
    });

    return updated;
  }

  async update(id: string, dto: UpdateEmployeeWarningDto, actorId: string) {
    const warning = await this.ensureWarningExists(id, this.getCompanyId());

    if (!EDITABLE_STATUSES.includes(warning.status)) {
      throw new BadRequestException('Solo se pueden editar amonestaciones en estado borrador');
    }

    const nextReason = (dto.reason ?? (warning as any).reason ?? warning.title).trim();
    const nextDetails = (dto.details ?? (warning as any).details ?? warning.description).trim();
    if (!nextReason) throw new BadRequestException('El motivo es obligatorio');
    if (!nextDetails) throw new BadRequestException('El detalle de los hechos es obligatorio');

    const warningDate = dto.warningDate ? new Date(dto.warningDate) : warning.warningDate;
    const incidentDate = dto.incidentDate ? new Date(dto.incidentDate) : warning.incidentDate;

    const generatedText = this.buildGeneratedText({
      warningDate,
      incidentDate,
      incidentTime: dto.incidentTime ?? (warning as any).incidentTime,
      incidentPlace: dto.incidentPlace ?? (warning as any).incidentPlace,
      reason: nextReason,
      details: nextDetails,
      employeeName: this.valueOrDefault((warning as any).employeeNameSnapshot ?? warning.employeeUser?.nombreCompleto),
      employeeCedula: this.valueOrDefault((warning as any).employeeCedulaSnapshot ?? warning.employeeUser?.cedula),
      employeePosition: this.valueOrDefault((warning as any).employeePositionSnapshot ?? warning.employeeUser?.workContractJobTitle),
      employeeDepartment: this.valueOrDefault((warning as any).employeeDepartmentSnapshot ?? warning.employeeUser?.workContractWorkLocation),
      companyName: this.valueOrDefault((warning as any).companyNameSnapshot),
      companyRnc: this.valueOrDefault((warning as any).companyRncSnapshot),
      companyAddress: this.valueOrDefault((warning as any).companyAddressSnapshot),
      issuerName: this.valueOrDefault(dto.issuedByNameSnapshot ?? (warning as any).issuedByNameSnapshot ?? warning.createdByUser?.nombreCompleto),
      issuerPosition: this.valueOrDefault(dto.issuedByPositionSnapshot ?? (warning as any).issuedByPositionSnapshot ?? warning.createdByUser?.workContractJobTitle),
    });

    const status = dto.saveAsDraft == null
      ? warning.status
      : dto.saveAsDraft
          ? EmployeeWarningStatus.DRAFT
          : ('ISSUED' as EmployeeWarningStatus);

    const updated = await this.prisma.employeeWarning.update({
      where: { id },
      data: {
        ...(dto.warningDate && { warningDate }),
        ...(dto.incidentDate && { incidentDate }),
        ...(dto.warningType && { warningType: dto.warningType }),
        ...(dto.reason !== undefined && { reason: nextReason, title: nextReason }),
        ...(dto.details !== undefined && { details: nextDetails, description: nextDetails }),
        ...(dto.incidentTime !== undefined && { incidentTime: this.cleanOptional(dto.incidentTime) }),
        ...(dto.incidentPlace !== undefined && { incidentPlace: this.cleanOptional(dto.incidentPlace) }),
        ...(dto.issuedByNameSnapshot !== undefined && { issuedByNameSnapshot: this.cleanOptional(dto.issuedByNameSnapshot) }),
        ...(dto.issuedByPositionSnapshot !== undefined && {
          issuedByPositionSnapshot: this.cleanOptional(dto.issuedByPositionSnapshot),
        }),
        ...(dto.internalNotes !== undefined && { internalNotes: this.cleanOptional(dto.internalNotes) }),
        status,
        generatedText,
      } as any,
      include: WARNING_INCLUDE,
    });

    const pdfBuffer = await this.generatePdfBuffer(updated as any);
    const objectKey = `employee-warnings/${id}/amonestacion-${updated.warningNumber}.pdf`;
    await this.r2.putObject({ objectKey, body: pdfBuffer, contentType: 'application/pdf' });
    const pdfUrl = this.r2.buildPublicUrl(objectKey);
    const withPdf = await this.prisma.employeeWarning.update({
      where: { id },
      data: { pdfUrl },
      include: WARNING_INCLUDE,
    });

    await this.logAudit({
      warningId: id,
      action: 'updated',
      actorUserId: actorId,
      oldStatus: warning.status,
      newStatus: status,
      metadata: { reason: nextReason },
    });

    return withPdf;
  }

  async deleteDraft(id: string, actorId: string) {
    const warning = await this.ensureWarningExists(id, this.getCompanyId());

    if (warning.status !== EmployeeWarningStatus.DRAFT) {
      throw new BadRequestException('Solo se pueden eliminar amonestaciones en borrador');
    }

    for (const ev of warning.evidences) {
      if (ev.storageKey) {
        try {
          await this.r2.deleteObject(ev.storageKey);
        } catch {
          // best effort
        }
      }
    }

    await this.prisma.employeeWarning.delete({ where: { id } });

    await this.logAudit({
      warningId: id,
      action: 'deleted',
      actorUserId: actorId,
      oldStatus: warning.status,
    });

    return { deleted: true };
  }

  async annul(id: string, dto: AnnulEmployeeWarningDto, actorId: string) {
    const warning = await this.ensureWarningExists(id, this.getCompanyId());

    if (warning.status === EmployeeWarningStatus.ANNULLED) {
      throw new BadRequestException('La amonestacion ya esta anulada');
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

  async uploadEvidence(
    id: string,
    file: { buffer: Buffer; originalname: string; mimetype: string },
    actorId: string,
  ) {
    const warning = await this.ensureWarningExists(id, this.getCompanyId());

    if (!EDITABLE_STATUSES.includes(warning.status)) {
      throw new BadRequestException('Solo se pueden subir evidencias a amonestaciones en borrador');
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

  async findMyPending(userId: string) {
    const companyId = this.getCompanyId();
    const items = await this.prisma.employeeWarning.findMany({
      where: {
        companyId,
        employeeUserId: userId,
        status: { not: EmployeeWarningStatus.ANNULLED },
      } as any,
      include: WARNING_INCLUDE,
      orderBy: { warningDate: 'desc' },
      take: 20,
    });
    return items;
  }

  async findMyWarning(id: string, userId: string) {
    const companyId = this.getCompanyId();
    const warning = await this.prisma.employeeWarning.findFirst({
      where: { id, companyId, employeeUserId: userId },
      include: WARNING_INCLUDE,
    });
    if (!warning) throw new NotFoundException('Amonestacion no encontrada');
    return warning;
  }

  async getMyPdfBytes(
    id: string,
    userId: string,
  ): Promise<{ body: Buffer; contentType: string; filename: string }> {
    const companyId = this.getCompanyId();
    const warning = await this.prisma.employeeWarning.findFirst({
      where: { id, companyId, employeeUserId: userId },
      select: { id: true, pdfUrl: true, warningNumber: true },
    });

    if (!warning) throw new NotFoundException('Amonestacion no encontrada');
    if (!warning.pdfUrl) {
      throw new NotFoundException('El PDF de esta amonestacion aun no esta disponible.');
    }

    let objectKey: string;
    try {
      const url = new URL(warning.pdfUrl);
      objectKey = url.pathname.replace(/^\//, '');
    } catch {
      objectKey = warning.pdfUrl;
    }

    const { body, contentType } = await this.r2.getObject(objectKey);
    const filename = `amonestacion-${warning.warningNumber}.pdf`;
    return { body, contentType: contentType ?? 'application/pdf', filename };
  }

  async getPdfBytes(
    id: string,
  ): Promise<{ body: Buffer; contentType: string; filename: string }> {
    const companyId = this.getCompanyId();
    const warning = await this.prisma.employeeWarning.findFirst({
      where: { id, companyId },
      select: { id: true, pdfUrl: true, warningNumber: true },
    });

    if (!warning) throw new NotFoundException('Amonestacion no encontrada');
    if (!warning.pdfUrl) {
      throw new NotFoundException('El PDF de esta amonestacion aun no esta disponible.');
    }

    let objectKey: string;
    try {
      const url = new URL(warning.pdfUrl);
      objectKey = url.pathname.replace(/^\//, '');
    } catch {
      objectKey = warning.pdfUrl;
    }

    const { body, contentType } = await this.r2.getObject(objectKey);
    const filename = `amonestacion-${warning.warningNumber}.pdf`;
    return { body, contentType: contentType ?? 'application/pdf', filename };
  }

  private async generatePdfBuffer(warning: any): Promise<Buffer> {
    return new Promise((resolve, reject) => {
      const chunks: Buffer[] = [];
      const doc = new PDFDocument({ margin: 48, size: 'LETTER' });

      doc.on('data', (chunk: Buffer) => chunks.push(chunk));
      doc.on('end', () => resolve(Buffer.concat(chunks)));
      doc.on('error', reject);

      const statusLabels: Record<string, string> = {
        DRAFT: 'Borrador',
        ISSUED: 'Emitida',
        ANNULLED: 'Anulada',
        PENDING_SIGNATURE: 'Pendiente de firma (historico)',
        SIGNED: 'Firmada (historico)',
        REFUSED_TO_SIGN: 'Negativa a firmar (historico)',
        ARCHIVED: 'Archivada',
      };

      const typeLabels: Record<string, string> = {
        VERBAL_DOCUMENTED: 'Verbal documentada',
        WRITTEN: 'Escrita',
        REINCIDENCE: 'Reincidencia',
        OTHER: 'Otra',
      };

      const fmt = (d: Date | null | undefined) => {
        if (!d) return 'No registrado';
        return new Intl.DateTimeFormat('es-DO', {
          day: '2-digit',
          month: '2-digit',
          year: 'numeric',
        }).format(new Date(d));
      };

      // ── Header profesional ─────────────────────────────────────────
      doc
        .fillColor('#1a1a2e')
        .fontSize(18)
        .font('Helvetica-Bold')
        .text(this.valueOrDefault(warning.companyNameSnapshot), { align: 'center' });
      doc
        .fillColor('#666666')
        .fontSize(10)
        .font('Helvetica')
        .text(`RNC: ${this.valueOrDefault(warning.companyRncSnapshot)}`, { align: 'center' });
      doc.text(this.valueOrDefault(warning.companyAddressSnapshot), { align: 'center' });

      // Línea separadora
      doc.moveTo(48, doc.y).lineTo(552, doc.y).strokeColor('#cccccc').lineWidth(1.5).stroke();
      doc.moveDown(0.6);

      // ── Título principal ──────────────────────────────────────────
      doc
        .fillColor('#000000')
        .fontSize(14)
        .font('Helvetica-Bold')
        .text('AMONESTACIÓN LABORAL', { align: 'center' });
      doc.moveDown(0.5);

      // ── Información del documento ─────────────────────────────────
      const infoX = 48;
      const infoColWidth = 250;
      doc.font('Helvetica-Bold').fontSize(9).fillColor('#333333');

      doc.text('No. Amonestación:', infoX, doc.y, { width: 120 });
      doc.font('Helvetica').text(warning.warningNumber, infoX + 130, doc.y - 13);

      doc.font('Helvetica-Bold').text('Estado:', infoX, doc.y, { width: 120 });
      doc.font('Helvetica').text(statusLabels[warning.status] ?? warning.status, infoX + 130, doc.y - 13);

      doc.font('Helvetica-Bold').text('Tipo:', infoX, doc.y, { width: 120 });
      doc
        .font('Helvetica')
        .text(typeLabels[warning.warningType] ?? warning.warningType ?? 'No registrado', infoX + 130, doc.y - 13);

      doc.moveDown(1);
      doc.moveTo(48, doc.y).lineTo(552, doc.y).strokeColor('#e0e0e0').lineWidth(1).stroke();
      doc.moveDown(0.5);

      // ── Datos del empleado ────────────────────────────────────────
      doc.font('Helvetica-Bold').fontSize(11).fillColor('#1a1a2e').text('EMPLEADO');
      doc.moveDown(0.3);

      const employeeName = this.valueOrDefault(warning.employeeNameSnapshot ?? warning.employeeUser?.nombreCompleto);
      const employeeCedula = this.valueOrDefault(warning.employeeCedulaSnapshot ?? warning.employeeUser?.cedula);
      const employeePosition = this.valueOrDefault(warning.employeePositionSnapshot ?? warning.employeeUser?.workContractJobTitle);
      const employeeDept = this.valueOrDefault(warning.employeeDepartmentSnapshot ?? warning.employeeUser?.workContractWorkLocation);
      const employeePhone = this.valueOrDefault(warning.employeePhoneSnapshot ?? warning.employeeUser?.telefono);

      doc.font('Helvetica').fontSize(10).fillColor('#333333');
      doc.text(`Nombre: ${employeeName}`);
      doc.text(`Cédula: ${employeeCedula}`);
      doc.text(`Cargo: ${employeePosition}`);
      doc.text(`Departamento/Área: ${employeeDept}`);
      doc.text(`Teléfono: ${employeePhone}`);
      doc.moveDown(0.4);

      // ── Fechas e información del incidente ─────────────────────────
      doc.font('Helvetica-Bold').fontSize(11).fillColor('#1a1a2e').text('INFORMACIÓN DEL HECHO');
      doc.moveDown(0.3);
      doc.font('Helvetica').fontSize(10).fillColor('#333333');
      doc.text(`Fecha de la amonestación: ${fmt(warning.warningDate)}`);
      doc.text(`Fecha del hecho: ${fmt(warning.incidentDate)}`);
      doc.text(`Hora aproximada: ${this.valueOrDefault(warning.incidentTime)}`);
      doc.text(`Lugar/Área: ${this.valueOrDefault(warning.incidentPlace)}`);
      doc.moveDown(0.4);

      // ── Motivo ────────────────────────────────────────────────────
      doc.font('Helvetica-Bold').fontSize(11).fillColor('#1a1a2e').text('MOTIVO');
      doc.moveDown(0.2);
      doc.font('Helvetica').fontSize(10).fillColor('#333333');
      const reason = (warning.reason ?? warning.title ?? '').toString().trim() || 'No registrado';
      doc.text(reason);
      doc.moveDown(0.4);

      // ── Detalle completo ──────────────────────────────────────────
      doc.font('Helvetica-Bold').fontSize(11).fillColor('#1a1a2e').text('DESCRIPCIÓN DETALLADA');
      doc.moveDown(0.2);
      const safeGeneratedText = (warning.generatedText ?? '').toString().trim();
      const fallbackText = warning.description?.toString().trim() || 'Sin contenido';
      doc.font('Helvetica').fontSize(9).fillColor('#333333');
      doc.text(safeGeneratedText || fallbackText, {
        width: 504,
        align: 'justify',
        lineGap: 2,
      });
      doc.moveDown(0.6);

      if ((warning.internalNotes ?? '').toString().trim().isNotEmpty) {
        doc.font('Helvetica-Bold').fontSize(10).fillColor('#1a1a2e').text('NOTAS INTERNAS');
        doc.moveDown(0.2);
        doc.font('Helvetica').fontSize(9).fillColor('#555555').fillOpacity(0.8);
        doc.text((warning.internalNotes ?? '').toString().trim(), {
          width: 504,
          align: 'justify',
          lineGap: 2,
        });
        doc.moveDown(0.6);
      }

      // ── Espacio de firma física ───────────────────────────────────
      doc.moveTo(48, doc.y).lineTo(552, doc.y).strokeColor('#e0e0e0').lineWidth(1).stroke();
      doc.moveDown(0.8);

      doc.font('Helvetica-Bold').fontSize(11).fillColor('#1a1a2e').text('FIRMAS');
      doc.moveDown(0.6);

      // Firma del emisor
      doc.font('Helvetica-Bold').fontSize(9).fillColor('#333333').text('Emitida por:');
      doc.moveDown(2.5);
      doc.moveTo(48, doc.y).lineTo(250, doc.y).strokeColor('#333333').lineWidth(1).stroke();
      doc.moveDown(0.2);
      doc.font('Helvetica').fontSize(9).fillColor('#333333');
      const issuerName = this.valueOrDefault(warning.issuedByNameSnapshot ?? warning.createdByUser?.nombreCompleto);
      doc.text(issuerName);

      // Firma del empleado
      doc.font('Helvetica-Bold').fontSize(9).fillColor('#333333').text('Firma del empleado / Acuse de recibo:', 300, doc.y - 3.2);
      doc.moveDown(2.5);
      doc.moveTo(300, doc.y).lineTo(552, doc.y).strokeColor('#333333').lineWidth(1).stroke();
      doc.moveDown(0.2);
      doc.font('Helvetica').fontSize(9).fillColor('#999999');
      doc.text('(Firma manuscrita del colaborador)', 300);

      // ── Pie de página ─────────────────────────────────────────────
      doc.moveDown(0.8);
      doc.moveTo(48, doc.y).lineTo(552, doc.y).strokeColor('#e0e0e0').lineWidth(1).stroke();
      doc.moveDown(0.3);
      doc.font('Helvetica').fontSize(8).fillColor('#999999').text(
        `Documento generado: ${new Date().toLocaleString('es-DO')} | Sistema FullTech | Este documento debe ser impreso y firmado físicamente`,
        { align: 'center' },
      );

      if (warning.status === 'ANNULLED') {
        doc.moveDown(0.5);
        doc
          .fillColor('#cc0000')
          .fontSize(9)
          .font('Helvetica-Bold')
          .text('⚠ DOCUMENTO ANULADO', { align: 'center' });
        doc
          .font('Helvetica')
          .fontSize(8)
          .text(`Anulado el ${fmt(warning.annulledAt)} - Motivo: ${warning.annulmentReason ?? 'No especificado'}`, {
            align: 'center',
          });
      }

      doc.end();
    });
  }
}
