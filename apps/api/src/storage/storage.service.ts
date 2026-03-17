import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { randomUUID } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { Role, ServiceUpdateType } from '@prisma/client';
import { R2Service } from './r2.service';
import { CatalogRealtimeRelayService } from '../products/catalog-realtime-relay.service';
import {
  assertValidObjectKeyForService,
  buildServiceObjectKey,
  inferMediaType,
  isAllowedContentType,
  parseIntEnv,
  sanitizeFileName,
} from './helpers/storage_helpers';
import { Prisma } from '@prisma/client';

type AuthUser = { id: string; role: Role };

@Injectable()
export class StorageService {
  private _techViewAllCache: { value: boolean; at: number } | null = null;

  constructor(
    private readonly prisma: PrismaService,
    private readonly r2: R2Service,
    private readonly realtime: CatalogRealtimeRelayService,
  ) {}

  private isAdminLike(role: Role) {
    return role === Role.ADMIN || role === Role.ASISTENTE;
  }

  private async techCanViewAllServices(): Promise<boolean> {
    const now = Date.now();
    const cached = this._techViewAllCache;
    if (cached && now - cached.at < 10_000) return cached.value;

    try {
      const cfg = await this.prisma.appConfig.findUnique({
        where: { id: 'global' },
        select: { operationsTechCanViewAllServices: true },
      });
      const value = !!cfg?.operationsTechCanViewAllServices;
      this._techViewAllCache = { value, at: now };
      return value;
    } catch {
      this._techViewAllCache = { value: false, at: now };
      return false;
    }
  }

  private assertCanView(user: AuthUser, sellerId: string, assignedIds: string[], techViewAll: boolean) {
    if (this.isAdminLike(user.role)) return;
    if (user.role === Role.VENDEDOR && user.id === sellerId) return;
    if (user.role === Role.TECNICO) {
      if (techViewAll) return;
      if (assignedIds.includes(user.id)) return;
    }
    throw new ForbiddenException('No autorizado para ver este servicio');
  }

  private assertCanOperate(user: AuthUser, sellerId: string, assignedIds: string[]) {
    if (this.isAdminLike(user.role)) return;
    if (user.role === Role.TECNICO && assignedIds.includes(user.id)) return;
    if (user.role === Role.VENDEDOR && user.id === sellerId) return;
    throw new ForbiddenException('No autorizado para modificar este servicio');
  }

  private async getServiceOrThrow(user: AuthUser, serviceId: string, mode: 'view' | 'operate') {
    const service = await this.prisma.service.findFirst({
      where: { id: serviceId, isDeleted: false },
      include: { assignments: true },
    });
    if (!service) throw new NotFoundException('Servicio no encontrado');

    const assignedIds = service.assignments.map((a) => a.userId);
    const techViewAll = user.role === Role.TECNICO ? await this.techCanViewAllServices() : false;

    if (mode === 'view') {
      this.assertCanView(user, service.createdByUserId, assignedIds, techViewAll);
    } else {
      this.assertCanOperate(user, service.createdByUserId, assignedIds);
    }

    return service;
  }

  private limitsBytesFor(mediaType: 'image' | 'video' | 'document') {
    const imageMax = parseIntEnv('STORAGE_IMAGE_MAX_BYTES', 5 * 1024 * 1024);
    const videoMax = parseIntEnv('STORAGE_VIDEO_MAX_BYTES', 20 * 1024 * 1024);
    const docMax = parseIntEnv('STORAGE_DOCUMENT_MAX_BYTES', 10 * 1024 * 1024);

    if (mediaType === 'image') return imageMax;
    if (mediaType === 'video') return videoMax;
    return docMax;
  }

  private _decodeBase64File(payload: string) {
    const raw = payload.trim();
    if (!raw) throw new BadRequestException('signatureBase64 es requerido');

    const match = /^data:([^;]+);base64,(.+)$/s.exec(raw);
    const mimeType = (match?.[1] ?? '').trim();
    const base64Payload = (match?.[2] ?? raw).replace(/\s+/g, '');
    let buffer: Buffer;
    try {
      buffer = Buffer.from(base64Payload, 'base64');
    } catch {
      throw new BadRequestException('signatureBase64 inválido');
    }
    if (!buffer.length) {
      throw new BadRequestException('signatureBase64 inválido');
    }
    return { buffer, mimeType };
  }

  private _extForMimeType(mimeType: string) {
    switch (mimeType.trim().toLowerCase()) {
      case 'image/jpeg':
        return 'jpg';
      case 'image/webp':
        return 'webp';
      case 'image/png':
      default:
        return 'png';
    }
  }

  async presignUpload(user: AuthUser, dto: {
    serviceId: string;
    executionReportId?: string;
    fileName: string;
    contentType: string;
    kind: string;
    fileSize: number;
  }) {
    await this.getServiceOrThrow(user, dto.serviceId, 'operate');

    const contentType = dto.contentType.trim();
    if (!isAllowedContentType(contentType)) {
      throw new BadRequestException('contentType no permitido');
    }

    const fileSize = dto.fileSize;
    if (!Number.isFinite(fileSize) || fileSize <= 0) {
      throw new BadRequestException('fileSize inválido');
    }

    const mediaType = inferMediaType(contentType);
    const max = this.limitsBytesFor(mediaType);
    if (fileSize > max) {
      throw new BadRequestException(`Archivo excede el máximo permitido (${max} bytes)`);
    }

    if (dto.executionReportId) {
      const report = await this.prisma.serviceExecutionReport.findFirst({
        where: { id: dto.executionReportId, serviceId: dto.serviceId },
        select: { id: true },
      });
      if (!report) throw new BadRequestException('executionReportId inválido');
    }

    const safeOriginal = sanitizeFileName(dto.fileName);
    const objectKey = buildServiceObjectKey(dto.serviceId, safeOriginal);

    const expiresIn = parseIntEnv('STORAGE_PRESIGN_EXPIRES_SECONDS', 900);

    const uploadUrl = await this.r2.createPresignedPutUrl({
      objectKey,
      contentType,
      expiresInSeconds: expiresIn,
    });

    const publicUrl = this.r2.buildPublicUrl(objectKey);

    return {
      uploadUrl,
      objectKey,
      publicUrl,
      expiresIn,
      mediaType,
      mimeType: contentType,
    };
  }

  async confirmUpload(user: AuthUser, dto: {
    serviceId: string;
    executionReportId?: string | null;
    objectKey: string;
    publicUrl: string;
    fileName: string;
    mimeType: string;
    fileSize: number;
    kind: string;
    caption?: string;
    uploadedByUserId?: string;
    width?: number | null;
    height?: number | null;
    durationSeconds?: number | null;
  }) {
    await this.getServiceOrThrow(user, dto.serviceId, 'operate');

    if (dto.uploadedByUserId && dto.uploadedByUserId !== user.id) {
      throw new ForbiddenException('uploadedByUserId inválido');
    }

    assertValidObjectKeyForService(dto.serviceId, dto.objectKey);

    const mimeType = dto.mimeType.trim();
    if (!isAllowedContentType(mimeType)) {
      throw new BadRequestException('mimeType no permitido');
    }

    const mediaType = inferMediaType(mimeType);
    const max = this.limitsBytesFor(mediaType);
    if (dto.fileSize > max) {
      throw new BadRequestException(`Archivo excede el máximo permitido (${max} bytes)`);
    }

    if (dto.executionReportId) {
      const report = await this.prisma.serviceExecutionReport.findFirst({
        where: { id: dto.executionReportId, serviceId: dto.serviceId },
        select: { id: true },
      });
      if (!report) throw new BadRequestException('executionReportId inválido');
    }

    // Verify object exists in R2 and (best-effort) matches.
    const head = await this.r2.headObject(dto.objectKey);
    if (head.contentLength !== null && head.contentLength !== dto.fileSize) {
      throw new BadRequestException('fileSize no coincide con el objeto subido');
    }

    const publicUrl = dto.publicUrl.trim() || this.r2.buildPublicUrl(dto.objectKey);
    const caption = typeof dto.caption === 'string' ? dto.caption.trim() : '';
    const captionOrNull = caption.length ? caption.slice(0, 140) : null;

    const created = await this.prisma.$transaction(async (tx) => {
      const row = await tx.serviceFile.create({
        data: {
          serviceId: dto.serviceId,
          uploadedByUserId: user.id,
          fileUrl: publicUrl,
          // Flutter usa `fileType` como tipo lógico/kind. Guardamos el kind aquí
          // y dejamos el mimeType real en el campo `mimeType`.
          fileType: dto.kind,
          caption: captionOrNull,
          storageProvider: 'R2',
          objectKey: dto.objectKey,
          originalFileName: (dto.fileName ?? '').trim() || null,
          mimeType,
          mediaType,
          kind: dto.kind,
          fileSize: dto.fileSize,
          width: dto.width ?? null,
          height: dto.height ?? null,
          durationSeconds: dto.durationSeconds ?? null,
          executionReportId: dto.executionReportId ?? null,
        },
      });

      await tx.serviceUpdate.create({
        data: {
          serviceId: dto.serviceId,
          changedByUserId: user.id,
          type: ServiceUpdateType.FILE_UPLOAD,
          oldValue: Prisma.DbNull,
          newValue: {
            id: row.id,
            fileUrl: publicUrl,
            objectKey: dto.objectKey,
            mimeType,
            kind: dto.kind,
            mediaType,
            caption: captionOrNull,
          },
          message: captionOrNull ? `Archivo subido (R2): ${captionOrNull}` : 'Archivo subido (R2)',
        },
      });

      return row;
    });

    // Realtime: notify ops clients to refresh. Keep payload lightweight to avoid
    // duplicating operations normalization logic in storage.
    try {
      this.realtime.emitOps('service.event', {
        eventId: randomUUID(),
        happenedAt: new Date().toISOString(),
        type: 'service.file_uploaded',
        serviceId: dto.serviceId,
        service: { id: dto.serviceId },
        fileId: created.id,
        kind: dto.kind,
        actorUserId: user.id,
      });
    } catch {
      // ignore
    }

    return created;
  }

  async uploadClientSignature(user: AuthUser, dto: {
    serviceId: string;
    signatureBase64?: string;
    mimeType?: string;
    fileName?: string;
    signedAt?: string;
    fileBuffer?: Buffer;
    fileMimeType?: string;
    fileOriginalName?: string;
  }) {
    await this.getServiceOrThrow(user, dto.serviceId, 'operate');

    const decoded = dto.fileBuffer?.length
      ? { buffer: dto.fileBuffer, mimeType: (dto.fileMimeType ?? '').trim() }
      : this._decodeBase64File(dto.signatureBase64 ?? '');

    const mimeType = (dto.mimeType ?? decoded.mimeType).trim().toLowerCase();
    if (!mimeType || !isAllowedContentType(mimeType)) {
      throw new BadRequestException('mimeType no permitido');
    }

    const mediaType = inferMediaType(mimeType);
    if (mediaType !== 'image') {
      throw new BadRequestException('La firma debe ser una imagen válida');
    }

    const fileSize = decoded.buffer.length;
    const max = this.limitsBytesFor(mediaType);
    if (!Number.isFinite(fileSize) || fileSize <= 0) {
      throw new BadRequestException('Archivo inválido');
    }
    if (fileSize > max) {
      throw new BadRequestException(`Archivo excede el máximo permitido (${max} bytes)`);
    }

    const fallbackFileName = `firma-cliente-${Date.now()}.${this._extForMimeType(mimeType)}`;
    const safeOriginal = sanitizeFileName(
      (dto.fileName ?? '').trim() ||
        (dto.fileOriginalName ?? '').trim() ||
        fallbackFileName,
    );
    const objectKey = buildServiceObjectKey(dto.serviceId, safeOriginal);
    await this.r2.putObject({
      objectKey,
      body: decoded.buffer,
      contentType: mimeType,
    });

    const publicUrl = this.r2.buildPublicUrl(objectKey);
    const signedAt = dto.signedAt?.trim().length
      ? new Date(dto.signedAt)
      : new Date();
    if (Number.isNaN(signedAt.getTime())) {
      throw new BadRequestException('signedAt inválido');
    }

    const captionOrNull = 'Firma del cliente';
    const kind = 'client_signature';

    const created = await this.prisma.$transaction(async (tx) => {
      const row = await tx.serviceFile.create({
        data: {
          serviceId: dto.serviceId,
          uploadedByUserId: user.id,
          fileUrl: publicUrl,
          fileType: kind,
          caption: captionOrNull,
          storageProvider: 'R2',
          objectKey,
          originalFileName: safeOriginal,
          mimeType,
          mediaType,
          kind,
          fileSize,
        },
      });

      await tx.serviceUpdate.create({
        data: {
          serviceId: dto.serviceId,
          changedByUserId: user.id,
          type: ServiceUpdateType.FILE_UPLOAD,
          oldValue: Prisma.DbNull,
          newValue: {
            id: row.id,
            fileUrl: publicUrl,
            objectKey,
            mimeType,
            kind,
            mediaType,
            caption: captionOrNull,
            signedAt: signedAt.toISOString(),
          },
          message: 'Firma del cliente subida',
        },
      });

      return row;
    });

    try {
      this.realtime.emitOps('service.event', {
        eventId: randomUUID(),
        happenedAt: new Date().toISOString(),
        type: 'service.file_uploaded',
        serviceId: dto.serviceId,
        service: { id: dto.serviceId },
        fileId: created.id,
        kind,
        actorUserId: user.id,
      });
    } catch {
      // ignore
    }

    return {
      fileId: created.id,
      fileUrl: created.fileUrl,
      mimeType: created.mimeType,
      kind: created.kind,
      signedAt: signedAt.toISOString(),
      createdAt: created.createdAt.toISOString(),
    };
  }

  async listServiceFiles(user: AuthUser, serviceId: string, query: { kind?: string; mediaType?: string }) {
    await this.getServiceOrThrow(user, serviceId, 'view');

    const files = await this.prisma.serviceFile.findMany({
      where: {
        serviceId,
        deletedAt: null,
        ...(query.kind ? { kind: query.kind } : null),
        ...(query.mediaType ? { mediaType: query.mediaType } : null),
      },
      orderBy: { createdAt: 'desc' },
    });

    return files;
  }

  async getFile(user: AuthUser, id: string) {
    const file = await this.prisma.serviceFile.findFirst({ where: { id } });
    if (!file || file.deletedAt) throw new NotFoundException('Archivo no encontrado');

    await this.getServiceOrThrow(user, file.serviceId, 'view');
    return file;
  }

  async deleteFile(user: AuthUser, id: string) {
    const file = await this.prisma.serviceFile.findFirst({ where: { id } });
    if (!file || file.deletedAt) throw new NotFoundException('Archivo no encontrado');

    await this.getServiceOrThrow(user, file.serviceId, 'operate');

    if (file.storageProvider === 'R2' && file.objectKey) {
      await this.r2.deleteObject(file.objectKey);
    }

    await this.prisma.serviceFile.update({
      where: { id },
      data: { deletedAt: new Date() },
    });

    return { ok: true };
  }
}
