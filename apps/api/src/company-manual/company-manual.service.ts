import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { CompanyManualAudience, CompanyManualEntryKind, Prisma, Role } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CompanyManualQueryDto } from './dto/company-manual-query.dto';
import { UpsertCompanyManualDto } from './dto/upsert-company-manual.dto';

type CurrentUser = { id: string; role: Role };

@Injectable()
export class CompanyManualService {
  constructor(private readonly prisma: PrismaService) {}

  async resolveCompanyOwnerId(fallbackUserId: string) {
    const admin = await this.prisma.user.findFirst({
      where: { role: Role.ADMIN },
      orderBy: { createdAt: 'asc' },
      select: { id: true },
    });
    return admin?.id ?? fallbackUserId;
  }

  async list(user: CurrentUser, query: CompanyManualQueryDto) {
    const ownerId = await this.resolveCompanyOwnerId(user.id);
    const where = this.buildWhere(ownerId, user, query);
    const items = await this.prisma.companyManualEntry.findMany({
      where,
      orderBy: [{ sortOrder: 'asc' }, { updatedAt: 'desc' }, { title: 'asc' }],
    });
    return { items };
  }

  async summary(user: CurrentUser, seenAt?: string) {
    const ownerId = await this.resolveCompanyOwnerId(user.id);
    const where = this.buildWhere(ownerId, user, { includeHidden: false });

    const [count, latest] = await this.prisma.$transaction([
      this.prisma.companyManualEntry.count({ where }),
      this.prisma.companyManualEntry.aggregate({
        where,
        _max: { updatedAt: true },
      }),
    ]);

    let unreadCount = count;
    const latestUpdatedAt = latest._max.updatedAt ?? null;
    if (seenAt?.trim()) {
      const seenDate = new Date(seenAt);
      if (!Number.isNaN(seenDate.getTime())) {
        unreadCount = await this.prisma.companyManualEntry.count({
          where: { ...where, updatedAt: { gt: seenDate } },
        });
      }
    }

    return {
      totalCount: count,
      unreadCount,
      latestUpdatedAt: latestUpdatedAt?.toISOString() ?? null,
    };
  }

  async upsert(user: CurrentUser, dto: UpsertCompanyManualDto) {
    const ownerId = await this.resolveCompanyOwnerId(user.id);
    const title = dto.title.trim();
    const content = dto.content.trim();
    const summary = dto.summary?.trim();
    const moduleKey = dto.moduleKey?.trim().toLowerCase();
    const targetRoles = this.normalizeTargetRoles(dto.audience, dto.targetRoles);

    if (!title) throw new BadRequestException('El título es obligatorio');
    if (!content) throw new BadRequestException('El contenido es obligatorio');

    const data = {
      ownerId,
      title,
      summary: summary && summary.length > 0 ? summary : null,
      content,
      kind: dto.kind,
      audience: dto.audience,
      targetRoles,
      moduleKey: moduleKey && moduleKey.length > 0 ? moduleKey : null,
      published: dto.published ?? true,
      sortOrder: dto.sortOrder ?? 0,
      updatedByUserId: user.id,
    };

    if (dto.id) {
      const existing = await this.prisma.companyManualEntry.findFirst({
        where: { id: dto.id, ownerId },
        select: { id: true, createdByUserId: true },
      });
      if (!existing) {
        throw new NotFoundException('La entrada del manual no existe');
      }

      return this.prisma.companyManualEntry.update({
        where: { id: dto.id },
        data: { ...data, createdByUserId: existing.createdByUserId },
      });
    }

    return this.prisma.companyManualEntry.create({
      data: { ...data, createdByUserId: user.id },
    });
  }

  async remove(user: CurrentUser, id: string) {
    const ownerId = await this.resolveCompanyOwnerId(user.id);
    const existing = await this.prisma.companyManualEntry.findFirst({
      where: { id, ownerId },
      select: { id: true },
    });
    if (!existing) {
      throw new NotFoundException('La entrada del manual no existe');
    }

    await this.prisma.companyManualEntry.delete({ where: { id } });
    return { ok: true };
  }

  private normalizeTargetRoles(audience: CompanyManualAudience, targetRoles?: Role[]) {
    if (audience === CompanyManualAudience.GENERAL) return [];
    const uniqueRoles = Array.from(new Set((targetRoles ?? []).filter(Boolean)));
    if (uniqueRoles.length == 0) {
      throw new BadRequestException(
        'Debes indicar al menos un rol cuando la entrada es específica por rol',
      );
    }
    return uniqueRoles;
  }

  private buildWhere(
    ownerId: string,
    user: CurrentUser,
    query: Partial<CompanyManualQueryDto>,
  ): Prisma.CompanyManualEntryWhereInput {
    const where: Prisma.CompanyManualEntryWhereInput = { ownerId };

    if (query.kind) where.kind = query.kind as CompanyManualEntryKind;
    if (query.audience) where.audience = query.audience as CompanyManualAudience;
    if (query.moduleKey?.trim()) {
      where.moduleKey = query.moduleKey.trim().toLowerCase();
    }
    if (query.role) {
      where.targetRoles = { has: query.role as Role };
    }

    if (user.role !== Role.ADMIN || query.includeHidden !== true) {
      where.published = true;
    }

    if (user.role !== Role.ADMIN) {
      where.OR = [
        { audience: CompanyManualAudience.GENERAL },
        {
          audience: CompanyManualAudience.ROLE_SPECIFIC,
          targetRoles: { has: user.role },
        },
      ];
    }

    return where;
  }
}