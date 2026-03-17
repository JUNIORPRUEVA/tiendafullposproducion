import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { Prisma, Role, ServicePhaseType } from '@prisma/client';
import { RedisService } from '../common/redis/redis.service';
import { PrismaService } from '../prisma/prisma.service';
import { CreateTechnicalVisitDto } from './dto/create-technical-visit.dto';
import { UpdateTechnicalVisitDto } from './dto/update-technical-visit.dto';

type AuthUser = { id: string; role: Role };

const TECHNICAL_VISIT_BY_ORDER_CACHE_PATTERN = 'technical-visits:order:*';

@Injectable()
export class TechnicalVisitsService {
  private readonly logger = new Logger(TechnicalVisitsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
  ) {}

  private buildVisitByOrderCacheKey(orderId: string) {
    return `technical-visits:order:${orderId.trim()}`;
  }

  private async invalidateTechnicalVisitCache(reason: string, orderId?: string) {
    const deleted = orderId
      ? await this.redis.del(this.buildVisitByOrderCacheKey(orderId))
      : await this.redis.delByPattern(TECHNICAL_VISIT_BY_ORDER_CACHE_PATTERN);
    if (this.redis.isEnabled()) {
      this.logger.log(`Redis INVALIDATE technical-visits reason=${reason} deleted=${deleted}`);
    }
  }

  private isAdminLike(role: Role) {
    return role === Role.ADMIN || role === Role.ASISTENTE;
  }

  private isSchemaMismatch(error: unknown) {
    const msg = (error as any)?.message ? String((error as any).message) : String(error);
    return /prisma/i.test(msg) && /(does not exist|unknown.*field|column .* does not exist|relation .* does not exist)/i.test(msg);
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

    if (mode === 'view' && !canView()) throw new ForbiddenException('No autorizado');
    if (mode === 'operate' && !canOperate()) throw new ForbiddenException('No autorizado');

    return service;
  }

  async create(user: AuthUser, dto: CreateTechnicalVisitDto) {
    const orderId = (dto.order_id ?? '').trim();
    const technicianId = (dto.technician_id ?? '').trim();
    if (!orderId || !technicianId) throw new BadRequestException('order_id y technician_id son requeridos');

    const service = await this.getServiceOrThrow(user, orderId, 'operate');

    if (service.currentPhase !== ServicePhaseType.LEVANTAMIENTO) {
      throw new BadRequestException('Este servicio no está en fase LEVANTAMIENTO');
    }

    // Techs can only create their own report.
    if (user.role === Role.TECNICO && user.id !== technicianId) {
      throw new ForbiddenException('El técnico solo puede crear su propio reporte');
    }

    const tech = await this.prisma.user.findFirst({
      where: { id: technicianId, blocked: false, role: Role.TECNICO },
      select: { id: true },
    });
    if (!tech && !this.isAdminLike(user.role)) {
      throw new BadRequestException('Técnico inválido');
    }

    const visitDate = dto.visit_date ? new Date(dto.visit_date) : new Date();
    if (Number.isNaN(visitDate.getTime())) throw new BadRequestException('visit_date inválido');

    try {
      const created = await this.prisma.technicalVisit.create({
        data: {
          orderId,
          technicianId,
          reportDescription: dto.report_description.trim(),
          installationNotes: dto.installation_notes.trim(),
          estimatedProducts: dto.estimated_products as unknown as Prisma.InputJsonValue,
          photos: (dto.photos ?? []) as unknown as Prisma.InputJsonValue,
          videos: (dto.videos ?? []) as unknown as Prisma.InputJsonValue,
          visitDate,
        },
      });
      await this.invalidateTechnicalVisitCache('technicalVisit.create', orderId);
      return created;
    } catch (e: any) {
      if (this.isSchemaMismatch(e)) {
        throw new ServiceUnavailableException('Módulo de levantamiento no disponible: falta aplicar migraciones.');
      }
      if (e?.code === 'P2002') {
        throw new BadRequestException('Este servicio ya tiene un reporte de levantamiento');
      }
      throw e;
    }
  }

  async getByOrder(user: AuthUser, orderId: string) {
    const id = (orderId ?? '').trim();
    if (!id) throw new BadRequestException('orderId inválido');

    await this.getServiceOrThrow(user, id, 'view');

    const cacheKey = this.buildVisitByOrderCacheKey(id);
    const cached = await this.redis.get<{ found: boolean; data: any | null }>(cacheKey);
    if (cached) {
      if (this.redis.isEnabled()) this.logger.log(`Redis HIT ${cacheKey}`);
      return cached.data;
    }
    if (this.redis.isEnabled()) this.logger.log(`Redis MISS ${cacheKey}`);

    try {
      const data = await this.prisma.technicalVisit.findUnique({ where: { orderId: id } });
      await this.redis.set(cacheKey, { found: data != null, data });
      return data;
    } catch (e) {
      if (this.isSchemaMismatch(e)) return null;
      throw e;
    }
  }

  async update(user: AuthUser, id: string, dto: UpdateTechnicalVisitDto) {
    const visitId = (id ?? '').trim();
    if (!visitId) throw new BadRequestException('id inválido');

    let existing: any;
    try {
      existing = await this.prisma.technicalVisit.findUnique({ where: { id: visitId } });
    } catch (e) {
      if (this.isSchemaMismatch(e)) {
        throw new ServiceUnavailableException('Módulo de levantamiento no disponible: falta aplicar migraciones.');
      }
      throw e;
    }
    if (!existing) throw new NotFoundException('Reporte no encontrado');

    await this.getServiceOrThrow(user, existing.orderId, 'operate');

    const data: Prisma.TechnicalVisitUpdateInput = {
      ...(dto.report_description !== undefined ? { reportDescription: dto.report_description.trim() } : {}),
      ...(dto.installation_notes !== undefined ? { installationNotes: dto.installation_notes.trim() } : {}),
      ...(dto.estimated_products !== undefined
        ? { estimatedProducts: dto.estimated_products as unknown as Prisma.InputJsonValue }
        : {}),
      ...(dto.photos !== undefined ? { photos: dto.photos as unknown as Prisma.InputJsonValue } : {}),
      ...(dto.videos !== undefined ? { videos: dto.videos as unknown as Prisma.InputJsonValue } : {}),
    };

    if (Object.keys(data).length === 0) {
      throw new BadRequestException('No hay cambios para guardar');
    }

    const updated = await this.prisma.technicalVisit.update({ where: { id: visitId }, data });
    await this.invalidateTechnicalVisitCache('technicalVisit.update', existing.orderId);
    return updated;
  }
}
