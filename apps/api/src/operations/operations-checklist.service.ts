import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Prisma, Role } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { OperationsService } from './operations-main.service';
import { CreateServiceChecklistCategoryDto } from './dto/create-service-checklist-category.dto';
import { CreateServiceChecklistPhaseDto } from './dto/create-service-checklist-phase.dto';
import { CreateServiceChecklistTemplateDto } from './dto/create-service-checklist-template.dto';
import { CreateServiceChecklistItemDto } from './dto/create-service-checklist-item.dto';
import { CheckServiceChecklistItemDto } from './dto/check-service-checklist-item.dto';

type AuthUser = { id: string; role: Role };
type SqlClient = PrismaService | Prisma.TransactionClient;

type LookupRow = {
  id: string;
  name: string;
  code: string;
  orderIndex?: number | null;
  createdAt: Date;
  updatedAt: Date;
};

type TemplateListRow = {
  templateId: string;
  title: string;
  categoryId: string;
  categoryName: string;
  categoryCode: string;
  phaseId: string;
  phaseName: string;
  phaseCode: string;
  phaseOrderIndex: number | null;
  itemId: string | null;
  itemLabel: string | null;
  itemRequired: boolean | null;
  itemOrderIndex: number | null;
};

type ServiceChecklistRow = {
  checklistId: string;
  templateId: string;
  title: string;
  categoryId: string;
  categoryName: string;
  categoryCode: string;
  phaseId: string;
  phaseName: string;
  phaseCode: string;
  phaseOrderIndex: number | null;
  serviceChecklistItemId: string | null;
  checklistItemId: string | null;
  itemLabel: string | null;
  itemRequired: boolean | null;
  itemOrderIndex: number | null;
  isChecked: boolean | null;
  checkedAt: Date | null;
  checkedById: string | null;
  checkedByName: string | null;
};

type ServiceChecklistItemLookupRow = {
  serviceChecklistItemId: string;
  serviceId: string;
};

@Injectable()
export class OperationsChecklistService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly operations: OperationsService,
  ) {}

  private assertAdmin(user: AuthUser) {
    if (
      user.role !== Role.ADMIN &&
      user.role !== Role.ASISTENTE &&
      user.role !== Role.VENDEDOR
    ) {
      throw new ForbiddenException(
        'No tienes permisos para configurar checklists',
      );
    }
  }

  private normalizeCode(raw: string) {
    return raw
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '_')
      .replace(/^_+|_+$/g, '');
  }

  private async findCategoryOrFail(categoryId: string) {
    const rows = await this.prisma.$queryRaw<Array<{ id: string }>>(
      Prisma.sql`SELECT id FROM service_categories WHERE id = ${categoryId}::uuid LIMIT 1`,
    );
    if (rows.length === 0) {
      throw new NotFoundException('Categoría de checklist no encontrada');
    }
  }

  private async findPhaseOrFail(phaseId: string) {
    const rows = await this.prisma.$queryRaw<Array<{ id: string }>>(
      Prisma.sql`SELECT id FROM service_phases WHERE id = ${phaseId}::uuid LIMIT 1`,
    );
    if (rows.length === 0) {
      throw new NotFoundException('Fase de checklist no encontrada');
    }
  }

  async listCategories() {
    return this.prisma.$queryRaw<LookupRow[]>(Prisma.sql`
      SELECT
        id,
        name,
        code,
        created_at AS "createdAt",
        updated_at AS "updatedAt"
      FROM service_categories
      ORDER BY name ASC
    `);
  }

  async createCategory(user: AuthUser, dto: CreateServiceChecklistCategoryDto) {
    this.assertAdmin(user);

    const name = dto.name.trim();
    const code = this.normalizeCode(
      dto.code?.trim().length ? dto.code!.trim() : name,
    );
    if (!code) {
      throw new BadRequestException('El código de la categoría es inválido');
    }

    const rows = await this.prisma.$queryRaw<LookupRow[]>(Prisma.sql`
      INSERT INTO service_categories (id, name, code, created_at, updated_at)
      VALUES (gen_random_uuid(), ${name}, ${code}, now(), now())
      RETURNING
        id,
        name,
        code,
        created_at AS "createdAt",
        updated_at AS "updatedAt"
    `);
    return rows[0];
  }

  async listPhases() {
    return this.prisma.$queryRaw<LookupRow[]>(Prisma.sql`
      SELECT
        id,
        name,
        code,
        order_index AS "orderIndex",
        created_at AS "createdAt",
        updated_at AS "updatedAt"
      FROM service_phases
      ORDER BY order_index ASC, name ASC
    `);
  }

  async createPhase(user: AuthUser, dto: CreateServiceChecklistPhaseDto) {
    this.assertAdmin(user);

    const name = dto.name.trim();
    const code = this.normalizeCode(
      dto.code?.trim().length ? dto.code!.trim() : name,
    );
    if (!code) {
      throw new BadRequestException('El código de la fase es inválido');
    }

    const rows = await this.prisma.$queryRaw<LookupRow[]>(Prisma.sql`
      INSERT INTO service_phases (id, name, code, order_index, created_at, updated_at)
      VALUES (gen_random_uuid(), ${name}, ${code}, ${dto.orderIndex ?? 0}, now(), now())
      RETURNING
        id,
        name,
        code,
        order_index AS "orderIndex",
        created_at AS "createdAt",
        updated_at AS "updatedAt"
    `);
    return rows[0];
  }

  async createTemplate(user: AuthUser, dto: CreateServiceChecklistTemplateDto) {
    this.assertAdmin(user);
    await Promise.all([
      this.findCategoryOrFail(dto.categoryId),
      this.findPhaseOrFail(dto.phaseId),
    ]);

    const title = dto.title.trim();
    const rows = await this.prisma.$queryRaw<
      Array<{
        id: string;
        title: string;
        categoryId: string;
        phaseId: string;
        createdAt: Date;
        updatedAt: Date;
      }>
    >(Prisma.sql`
      INSERT INTO checklist_templates (id, category_id, phase_id, title, created_at, updated_at)
      VALUES (gen_random_uuid(), ${dto.categoryId}::uuid, ${dto.phaseId}::uuid, ${title}, now(), now())
      RETURNING
        id,
        title,
        category_id AS "categoryId",
        phase_id AS "phaseId",
        created_at AS "createdAt",
        updated_at AS "updatedAt"
    `);
    return rows[0];
  }

  async createItem(user: AuthUser, dto: CreateServiceChecklistItemDto) {
    this.assertAdmin(user);

    const templateRows = await this.prisma.$queryRaw<Array<{ id: string }>>(
      Prisma.sql`SELECT id FROM checklist_templates WHERE id = ${dto.templateId}::uuid LIMIT 1`,
    );
    if (templateRows.length === 0) {
      throw new NotFoundException('Plantilla de checklist no encontrada');
    }

    const label = dto.label.trim();
    const rows = await this.prisma.$queryRaw<
      Array<{
        id: string;
        templateId: string;
        label: string;
        isRequired: boolean;
        orderIndex: number;
        createdAt: Date;
        updatedAt: Date;
      }>
    >(Prisma.sql`
      INSERT INTO checklist_items (id, template_id, label, is_required, order_index, created_at, updated_at)
      VALUES (
        gen_random_uuid(),
        ${dto.templateId}::uuid,
        ${label},
        ${dto.isRequired ?? true},
        ${dto.orderIndex ?? 0},
        now(),
        now()
      )
      RETURNING
        id,
        template_id AS "templateId",
        label,
        is_required AS "isRequired",
        order_index AS "orderIndex",
        created_at AS "createdAt",
        updated_at AS "updatedAt"
    `);
    return rows[0];
  }

  async listTemplates(filters?: { categoryId?: string; phaseId?: string }) {
    const where: Prisma.Sql[] = [];
    const categoryId = filters?.categoryId?.trim() ?? '';
    const phaseId = filters?.phaseId?.trim() ?? '';

    if (categoryId.length > 0) {
      where.push(
        Prisma.sql`ct.category_id = ${categoryId}::uuid`,
      );
    }
    if (phaseId.length > 0) {
      where.push(Prisma.sql`ct.phase_id = ${phaseId}::uuid`);
    }

    const predicate = where.length === 0
      ? Prisma.empty
      : Prisma.sql`WHERE ${Prisma.join(where, ' AND ')}`;

    const rows = await this.prisma.$queryRaw<TemplateListRow[]>(Prisma.sql`
      SELECT
        ct.id AS "templateId",
        ct.title,
        sc.id AS "categoryId",
        sc.name AS "categoryName",
        sc.code AS "categoryCode",
        sp.id AS "phaseId",
        sp.name AS "phaseName",
        sp.code AS "phaseCode",
        sp.order_index AS "phaseOrderIndex",
        ci.id AS "itemId",
        ci.label AS "itemLabel",
        ci.is_required AS "itemRequired",
        ci.order_index AS "itemOrderIndex"
      FROM checklist_templates ct
      INNER JOIN service_categories sc ON sc.id = ct.category_id
      INNER JOIN service_phases sp ON sp.id = ct.phase_id
      LEFT JOIN checklist_items ci ON ci.template_id = ct.id
      ${predicate}
      ORDER BY sp.order_index ASC, sp.name ASC, ct.title ASC, ci.order_index ASC, ci.label ASC
    `);
    return this.groupTemplateRows(rows);
  }

  async ensureServiceChecklists(service: { id: string; category?: string | null }) {
    const serviceId = service.id.trim();
    const categoryCode = this.normalizeCode((service.category ?? '').toString());
    if (!serviceId || !categoryCode) return;
    await this.ensureServiceChecklistsWithClient(
      this.prisma,
      serviceId,
      categoryCode,
    );
  }

  private async ensureServiceChecklistsWithClient(
    db: SqlClient,
    serviceId: string,
    categoryCode: string,
  ) {
    await db.$executeRaw(Prisma.sql`
      INSERT INTO service_checklists (id, service_order_id, template_id, created_at, updated_at)
      SELECT gen_random_uuid(), ${serviceId}::uuid, ct.id, now(), now()
      FROM checklist_templates ct
      INNER JOIN service_categories sc ON sc.id = ct.category_id
      WHERE sc.code = ${categoryCode}
      ON CONFLICT (service_order_id, template_id)
      DO UPDATE SET updated_at = now()
    `);

    await db.$executeRaw(Prisma.sql`
      INSERT INTO service_checklist_items (
        id,
        checklist_id,
        checklist_item_id,
        is_checked,
        checked_at,
        checked_by,
        created_at,
        updated_at
      )
      SELECT
        gen_random_uuid(),
        scx.id,
        ci.id,
        false,
        NULL,
        NULL,
        now(),
        now()
      FROM service_checklists scx
      INNER JOIN checklist_templates ct ON ct.id = scx.template_id
      INNER JOIN service_categories sc ON sc.id = ct.category_id
      INNER JOIN checklist_items ci ON ci.template_id = ct.id
      LEFT JOIN service_checklist_items sci
        ON sci.checklist_id = scx.id
       AND sci.checklist_item_id = ci.id
      WHERE scx.service_order_id = ${serviceId}::uuid
        AND sc.code = ${categoryCode}
        AND sci.id IS NULL
    `);
  }

  async getServiceChecklists(user: AuthUser, serviceId: string) {
    const service = await this.operations.findOne(user, serviceId);
    await this.ensureServiceChecklists({
      id: service.id,
      category: service.category,
    });

    const rows = await this.prisma.$queryRaw<ServiceChecklistRow[]>(Prisma.sql`
      SELECT
        scx.id AS "checklistId",
        ct.id AS "templateId",
        ct.title,
        sc.id AS "categoryId",
        sc.name AS "categoryName",
        sc.code AS "categoryCode",
        sp.id AS "phaseId",
        sp.name AS "phaseName",
        sp.code AS "phaseCode",
        sp.order_index AS "phaseOrderIndex",
        sci.id AS "serviceChecklistItemId",
        ci.id AS "checklistItemId",
        ci.label AS "itemLabel",
        ci.is_required AS "itemRequired",
        ci.order_index AS "itemOrderIndex",
        sci.is_checked AS "isChecked",
        sci.checked_at AS "checkedAt",
        sci.checked_by AS "checkedById",
        u."nombreCompleto" AS "checkedByName"
      FROM service_checklists scx
      INNER JOIN checklist_templates ct ON ct.id = scx.template_id
      INNER JOIN service_categories sc ON sc.id = ct.category_id
      INNER JOIN service_phases sp ON sp.id = ct.phase_id
      LEFT JOIN service_checklist_items sci ON sci.checklist_id = scx.id
      LEFT JOIN checklist_items ci ON ci.id = sci.checklist_item_id
      LEFT JOIN "users" u ON u.id = sci.checked_by
      WHERE scx.service_order_id = ${serviceId}::uuid
      ORDER BY sp.order_index ASC, sp.name ASC, ct.title ASC, ci.order_index ASC, ci.label ASC
    `);

    return {
      serviceId: service.id,
      currentPhase: service.currentPhase,
      orderState: service.orderState,
      category: {
        code: this.normalizeCode((service.category ?? '').toString()),
        label: (service.category ?? '').toString(),
      },
      templates: this.groupServiceChecklistRows(rows),
    };
  }

  async checkServiceChecklistItem(
    user: AuthUser,
    serviceChecklistItemId: string,
    dto: CheckServiceChecklistItemDto,
  ) {
    const rows = await this.prisma.$queryRaw<ServiceChecklistItemLookupRow[]>(
      Prisma.sql`
        SELECT
          sci.id AS "serviceChecklistItemId",
          scx.service_order_id AS "serviceId"
        FROM service_checklist_items sci
        INNER JOIN service_checklists scx ON scx.id = sci.checklist_id
        WHERE sci.id = ${serviceChecklistItemId}::uuid
        LIMIT 1
      `,
    );
    const row = rows[0];
    if (!row) {
      throw new NotFoundException('Ítem de checklist no encontrado');
    }

    await this.operations.findOne(user, row.serviceId);

    const checkedAt = dto.isChecked ? new Date() : null;
    const checkedById = dto.isChecked ? user.id : null;

    const updatedRows = await this.prisma.$queryRaw<
      Array<{
        id: string;
        isChecked: boolean;
        checkedAt: Date | null;
        checkedById: string | null;
      }>
    >(Prisma.sql`
      UPDATE service_checklist_items
      SET
        is_checked = ${dto.isChecked},
        checked_at = ${checkedAt},
        checked_by = ${checkedById},
        updated_at = now()
      WHERE id = ${serviceChecklistItemId}::uuid
      RETURNING
        id,
        is_checked AS "isChecked",
        checked_at AS "checkedAt",
        checked_by AS "checkedById"
    `);
    return updatedRows[0];
  }

  private groupTemplateRows(rows: TemplateListRow[]) {
    const templates = new Map<string, any>();

    for (const row of rows) {
      let current = templates.get(row.templateId);
      if (!current) {
        current = {
          id: row.templateId,
          title: row.title,
          category: {
            id: row.categoryId,
            name: row.categoryName,
            code: row.categoryCode,
          },
          phase: {
            id: row.phaseId,
            name: row.phaseName,
            code: row.phaseCode,
            orderIndex: row.phaseOrderIndex ?? 0,
          },
          items: [],
        };
        templates.set(row.templateId, current);
      }

      if (row.itemId) {
        current.items.push({
          id: row.itemId,
          label: row.itemLabel ?? '',
          isRequired: row.itemRequired ?? true,
          orderIndex: row.itemOrderIndex ?? 0,
        });
      }
    }

    return Array.from(templates.values());
  }

  private groupServiceChecklistRows(rows: ServiceChecklistRow[]) {
    const templates = new Map<string, any>();

    for (const row of rows) {
      let current = templates.get(row.checklistId);
      if (!current) {
        current = {
          id: row.checklistId,
          templateId: row.templateId,
          title: row.title,
          category: {
            id: row.categoryId,
            name: row.categoryName,
            code: row.categoryCode,
          },
          phase: {
            id: row.phaseId,
            name: row.phaseName,
            code: row.phaseCode,
            orderIndex: row.phaseOrderIndex ?? 0,
          },
          items: [],
        };
        templates.set(row.checklistId, current);
      }

      if (row.serviceChecklistItemId && row.checklistItemId) {
        current.items.push({
          id: row.serviceChecklistItemId,
          checklistItemId: row.checklistItemId,
          label: row.itemLabel ?? '',
          isRequired: row.itemRequired ?? true,
          orderIndex: row.itemOrderIndex ?? 0,
          isChecked: row.isChecked == true,
          checkedAt: row.checkedAt?.toISOString() ?? null,
          checkedByUserId: row.checkedById,
          checkedByName: row.checkedByName,
        });
      }
    }

    return Array.from(templates.values());
  }
}
