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

  async deleteWarning(id: string, actorId: string) {
    const warning = await this.ensureWarningExists(id, this.getCompanyId());

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
    // Flujo de firma desactivado: no se deben exponer pendientes al colaborador.
    void userId;
    return [];
  }

  async findMyWarning(id: string, userId: string) {
    // Flujo de firma desactivado: no se expone detalle al colaborador.
    void id;
    void userId;
    throw new NotFoundException('No hay amonestaciones disponibles para colaborador.');
  }

  async getMyPdfBytes(
    id: string,
    userId: string,
  ): Promise<{ body: Buffer; contentType: string; filename: string }> {
    // Flujo de firma desactivado: no se expone PDF al colaborador.
    void id;
    void userId;
    throw new NotFoundException('No hay amonestaciones disponibles para colaborador.');
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

      const companyNameRaw = (warning.companyNameSnapshot ?? '').toString().trim();
      const companyRncRaw = (warning.companyRncSnapshot ?? '').toString().trim();
      const companyAddressRaw = (warning.companyAddressSnapshot ?? '').toString().trim();
      const companyName = companyNameRaw.isNotEmpty ? companyNameRaw : 'FULLTECH, SRL';
      const companyRnc = companyRncRaw.isNotEmpty ? companyRncRaw : '133080206';
      const companyAddress =
        companyAddressRaw.isNotEmpty ? companyAddressRaw : 'Santo Domingo, Republica Dominicana';
      const companyPhone = '8295344286';

      const employeeName = this.valueOrDefault(
        warning.employeeNameSnapshot ?? warning.employeeUser?.nombreCompleto,
      );
      const employeeCedula = this.valueOrDefault(
        warning.employeeCedulaSnapshot ?? warning.employeeUser?.cedula,
      );
      const employeePosition = this.valueOrDefault(
        warning.employeePositionSnapshot ?? warning.employeeUser?.workContractJobTitle,
      );
      const employeeDepartment = this.valueOrDefault(
        warning.employeeDepartmentSnapshot ?? warning.employeeUser?.workContractWorkLocation,
      );

      const issuerName = this.valueOrDefault(
        warning.issuedByNameSnapshot ?? warning.createdByUser?.nombreCompleto,
      );
      const issuerPosition = this.valueOrDefault(
        warning.issuedByPositionSnapshot ?? warning.createdByUser?.workContractJobTitle,
      );

      const reason =
        (warning.reason ?? warning.title ?? '').toString().trim() || 'No registrado';
      const safeGeneratedText = (warning.generatedText ?? '').toString().trim();
      const fallbackText = warning.description?.toString().trim() || 'Sin contenido';
      const finalText = (safeGeneratedText || fallbackText).replace(/\s+/g, ' ').trim();

      const fitTextToHeight = (
        rawText: string,
        width: number,
        maxHeight: number,
        fontSize: number,
      ) => {
        const normalized = rawText.replace(/\s+/g, ' ').trim();
        if (!normalized) return 'No registrado';

        doc.font('Helvetica').fontSize(fontSize);
        const fullHeight = doc.heightOfString(normalized, {
          width,
          align: 'justify',
          lineGap: 1.2,
        });
        if (fullHeight <= maxHeight) return normalized;

        let low = 0;
        let high = normalized.length;
        let best = `${normalized.slice(0, 80).trim()}...`;

        while (low <= high) {
          const mid = Math.floor((low + high) / 2);
          const candidate = `${normalized.slice(0, mid).trim()}...`;
          const candidateHeight = doc.heightOfString(candidate, {
            width,
            align: 'justify',
            lineGap: 1.2,
          });

          if (candidateHeight <= maxHeight) {
            best = candidate;
            low = mid + 1;
          } else {
            high = mid - 1;
          }
        }

        return best;
      };

      // Header corporativo compacto
      doc
        .rect(48, 44, 504, 76)
        .fillAndStroke('#f9fbff', '#d7dde8');

      doc
        .fillColor('#10243f')
        .font('Helvetica-Bold')
        .fontSize(16)
        .text(companyName, 60, 56, { width: 480, align: 'center' });

      doc
        .fillColor('#4d5d73')
        .font('Helvetica')
        .fontSize(9.5)
        .text(`Tel: ${companyPhone} | RNC: ${companyRnc}`, 60, 78, {
          width: 480,
          align: 'center',
        });

      doc.text(companyAddress, 60, 94, { width: 480, align: 'center' });

      doc.moveTo(48, 130).lineTo(552, 130).strokeColor('#1f4b8f').lineWidth(1.4).stroke();

      // Titulo
      doc
        .fillColor('#0f172a')
        .font('Helvetica-Bold')
        .fontSize(13.5)
        .text('AMONESTACION LABORAL', 48, 142, { width: 504, align: 'center' });

      // Datos basicos
      const topDataY = 164;
      doc
        .roundedRect(48, topDataY, 504, 52, 4)
        .strokeColor('#d7dde8')
        .lineWidth(1)
        .stroke();

      doc.font('Helvetica-Bold').fontSize(9.5).fillColor('#1f2937');
      doc.text('Documento:', 60, topDataY + 10);
      doc.text('Fecha:', 60, topDataY + 27);
      doc.text('Tipo:', 320, topDataY + 10);
      doc.text('Incidente:', 320, topDataY + 27);

      doc.font('Helvetica').fontSize(9.5).fillColor('#374151');
      doc.text(warning.warningNumber, 128, topDataY + 10, { width: 170 });
      doc.text(fmt(warning.warningDate), 128, topDataY + 27, { width: 170 });
      doc.text(typeLabels[warning.warningType] ?? warning.warningType ?? 'No registrado', 360, topDataY + 10, {
        width: 170,
      });
      doc.text(fmt(warning.incidentDate), 380, topDataY + 27, { width: 150 });

      if (warning.status === 'ANNULLED') {
        doc
          .font('Helvetica-Bold')
          .fontSize(9)
          .fillColor('#b91c1c')
          .text('ANULADA', 488, topDataY + 10, { width: 54, align: 'right' });
      }

      // Destinatario
      let y = topDataY + 66;
      doc.font('Helvetica-Bold').fontSize(10).fillColor('#111827').text('Destinatario', 48, y);
      y += 15;

      doc.font('Helvetica').fontSize(9.5).fillColor('#1f2937');
      doc.text(`Nombre: ${employeeName}`, 48, y, { width: 504 });
      y += 13;
      doc.text(`Cedula: ${employeeCedula} | Cargo: ${employeePosition}`, 48, y, { width: 504 });
      y += 13;
      doc.text(`Departamento: ${employeeDepartment}`, 48, y, { width: 504 });
      y += 18;

      // Asunto y contexto
      doc
        .font('Helvetica-Bold')
        .fontSize(9.8)
        .fillColor('#0f172a')
        .text('Asunto:', 48, y, { continued: true })
        .font('Helvetica')
        .fillColor('#1f2937')
        .text(' Notificacion formal de amonestacion laboral.');
      y += 16;

      doc
        .font('Helvetica')
        .fontSize(9.6)
        .fillColor('#1f2937')
        .text(
          `Por medio de la presente, ${companyName} notifica la amonestacion laboral del colaborador indicado por incumplimiento de normas internas.`,
          48,
          y,
          { width: 504, align: 'justify', lineGap: 1.2 },
        );
      y = doc.y + 6;

      doc.font('Helvetica-Bold').fontSize(9.8).fillColor('#111827').text('Motivo:', 48, y);
      y = doc.y + 3;
      doc
        .font('Helvetica')
        .fontSize(9.4)
        .fillColor('#1f2937')
        .text(reason, 48, y, { width: 504, align: 'justify', lineGap: 1.2 });
      y = doc.y + 6;

      doc
        .font('Helvetica')
        .fontSize(9.2)
        .fillColor('#374151')
        .text(
          `Registro del incidente: ${fmt(warning.incidentDate)} | Hora: ${this.valueOrDefault(warning.incidentTime)} | Lugar: ${this.valueOrDefault(warning.incidentPlace)}.`,
          48,
          y,
          { width: 504, align: 'left', lineGap: 1.2 },
        );
      y = doc.y + 6;

      doc.font('Helvetica-Bold').fontSize(9.8).fillColor('#111827').text('Hechos:', 48, y);
      y = doc.y + 3;

      const signatureStartY = 618;
      const closingHeight = 26;
      const detailAvailableHeight = Math.max(56, signatureStartY - y - closingHeight - 10);
      const compactDetail = fitTextToHeight(finalText, 504, detailAvailableHeight, 9.2);

      doc
        .font('Helvetica')
        .fontSize(9.2)
        .fillColor('#1f2937')
        .text(compactDetail, 48, y, { width: 504, align: 'justify', lineGap: 1.2 });
      y = doc.y + 8;

      doc
        .font('Helvetica')
        .fontSize(9.4)
        .fillColor('#1f2937')
        .text(
          'Se solicita firma de recibido para constancia. Este documento se emite para archivo interno.',
          48,
          y,
          { width: 504, align: 'justify', lineGap: 1.2 },
        );
      y = Math.max(doc.y + 8, signatureStartY);

      // Bloque de firmas fijo (siempre en la misma hoja)
      doc.moveTo(48, y).lineTo(552, y).strokeColor('#d7dde8').lineWidth(1).stroke();
      y += 10;
      doc.font('Helvetica-Bold').fontSize(10).fillColor('#0f172a').text('Firmas', 48, y);
      y += 30;

      doc.moveTo(48, y).lineTo(250, y).strokeColor('#1f2937').lineWidth(1).stroke();
      doc.moveTo(300, y).lineTo(552, y).strokeColor('#1f2937').lineWidth(1).stroke();
      y += 5;

      doc.font('Helvetica-Bold').fontSize(8.8).fillColor('#1f2937');
      doc.text('Encargado responsable', 48, y, { width: 202, align: 'center' });
      doc.text('Empleado (acuse de recibo)', 300, y, { width: 252, align: 'center' });
      y += 13;

      doc.font('Helvetica').fontSize(8.6).fillColor('#4b5563');
      doc.text(`${issuerName}`, 48, y, { width: 202, align: 'center' });
      doc.text(`${employeeName}`, 300, y, { width: 252, align: 'center' });
      y += 11;
      doc.font('Helvetica').fontSize(8.1).fillColor('#6b7280');
      doc.text(`Cargo: ${issuerPosition}`, 48, y, { width: 202, align: 'center' });
      doc.text('Firma manuscrita requerida', 300, y, { width: 252, align: 'center' });

      // Pie institucional
      doc
        .moveTo(48, 740)
        .lineTo(552, 740)
        .strokeColor('#e5e7eb')
        .lineWidth(1)
        .stroke();

      doc
        .font('Helvetica')
        .fontSize(8)
        .fillColor('#6b7280')
        .text(
          `Emitido el ${new Date().toLocaleString('es-DO')} | ${companyName} | Documento para firma fisica`,
          48,
          746,
          { width: 504, align: 'center' },
        );

      doc.end();
    });
  }
}
