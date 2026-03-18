import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { createHash } from 'node:crypto';
import { Prisma, Role } from '@prisma/client';
import { RedisService } from '../common/redis/redis.service';
import { PrismaService } from '../prisma/prisma.service';
import { OperationsService } from './operations-main.service';
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
  type: string;
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

type ChecklistExecutionRow = {
  executionId: string;
  templateId: string;
  type: string;
  title: string;
  categoryId: string;
  categoryName: string;
  categoryCode: string;
  phaseId: string;
  phaseName: string;
  phaseCode: string;
  phaseOrderIndex: number | null;
  checklistItemId: string | null;
  itemLabel: string | null;
  itemRequired: boolean | null;
  itemOrderIndex: number | null;
  isChecked: boolean | null;
  checkedAt: Date | null;
  checkedById: string | null;
  checkedByName: string | null;
};

type ChecklistExecutionLookupRow = {
  executionId: string;
  serviceId: string;
};

type TemplateTypeCode = 'herramientas' | 'productos' | 'instalacion';

type PhaseSeed = {
  name: string;
  code: string;
  orderIndex: number;
};

type CategorySeed = {
  name: string;
  code: string;
};

const CHECKLIST_CATEGORIES_CACHE_KEY = 'checklist:categories';
const CHECKLIST_PHASES_CACHE_KEY = 'checklist:phases';
const CHECKLIST_TEMPLATES_CACHE_PATTERN = 'checklist:templates:*';
const CHECKLIST_SERVICE_CACHE_PATTERN = 'checklist:service:*';

@Injectable()
export class OperationsChecklistService {
  private readonly logger = new Logger(OperationsChecklistService.name);
  private readonly defaultCategories: CategorySeed[] = [
    { code: 'cameras', name: 'Cámaras' },
    { code: 'gate_motor', name: 'Motores de puertones' },
    { code: 'alarm', name: 'Alarma' },
    { code: 'electric_fence', name: 'Cerco eléctrico' },
    { code: 'intercom', name: 'Intercom' },
    { code: 'pos', name: 'Punto de ventas' },
  ];

  private readonly operationPhases: PhaseSeed[] = [
    { code: 'reserva', name: 'Reserva', orderIndex: 0 },
    { code: 'levantamiento', name: 'Levantamiento', orderIndex: 1 },
    { code: 'instalacion', name: 'Instalación', orderIndex: 2 },
    { code: 'mantenimiento', name: 'Mantenimiento', orderIndex: 3 },
    { code: 'garantia', name: 'Garantía', orderIndex: 4 },
  ];

  constructor(
    private readonly prisma: PrismaService,
    private readonly operations: OperationsService,
    private readonly redis: RedisService,
  ) {}

  private buildTemplateCacheKey(filters?: {
    categoryId?: string;
    phaseId?: string;
    categoryCode?: string;
    phaseCode?: string;
  }) {
    const scope = {
      categoryId: filters?.categoryId?.trim() ?? null,
      phaseId: filters?.phaseId?.trim() ?? null,
      categoryCode: this.normalizeCode(filters?.categoryCode ?? ''),
      phaseCode: this.normalizeCode(filters?.phaseCode ?? ''),
    };
    const hash = createHash('sha1').update(JSON.stringify(scope)).digest('hex');
    return `checklist:templates:${hash}`;
  }

  private buildServiceChecklistCacheKey(service: {
    id: string;
    currentPhase?: string | null;
    orderType?: string | null;
    orderState?: string | null;
    category?: string | null;
  }) {
    const effectivePhaseCode = this.resolveChecklistPhaseCodeForService({
      currentPhase: service.currentPhase,
      orderType: service.orderType,
    });
    const scope = {
      serviceId: service.id,
      currentPhase: effectivePhaseCode || null,
      orderType: this.normalizeCode((service.orderType ?? '').toString()) || null,
      orderState: (service.orderState ?? '').toString().trim() || null,
      category: this.canonicalChecklistCategoryCode((service.category ?? '').toString()),
    };
    const hash = createHash('sha1').update(JSON.stringify(scope)).digest('hex');
    return `checklist:service:${service.id}:${hash}`;
  }

  private async invalidateChecklistCache(reason: string, serviceId?: string) {
    const patterns = [CHECKLIST_TEMPLATES_CACHE_PATTERN, CHECKLIST_SERVICE_CACHE_PATTERN];
    const deletions = await Promise.all([
      this.redis.del(CHECKLIST_CATEGORIES_CACHE_KEY),
      this.redis.del(CHECKLIST_PHASES_CACHE_KEY),
      ...patterns.map((pattern) => this.redis.delByPattern(pattern)),
      ...(serviceId ? [this.redis.delByPattern(`checklist:service:${serviceId}:*`)] : []),
    ]);
    if (this.redis.isEnabled()) {
      this.logger.log(`Redis INVALIDATE checklist reason=${reason} deleted=${deletions.join(',')}`);
    }
  }

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

  private canonicalChecklistCategoryCode(raw: string) {
    const normalized = this.normalizeCode(raw);
    const aliases: Record<string, string> = {
      camaras: 'cameras',
      camaras_seguridad: 'cameras',
      motores_de_puertones: 'gate_motor',
      motores_de_portones: 'gate_motor',
      motores_portones: 'gate_motor',
      motor_de_porton: 'gate_motor',
      motor_porton: 'gate_motor',
      motor_puerton: 'gate_motor',
      motores_de_puerton: 'gate_motor',
      gate_motors: 'gate_motor',
      alarma: 'alarm',
      alarmas: 'alarm',
      cerco_electrico: 'electric_fence',
      cerca_electrica: 'electric_fence',
      electric_fence_system: 'electric_fence',
      interfono: 'intercom',
      interfonos: 'intercom',
      punto_de_venta: 'pos',
      punto_de_ventas: 'pos',
      punto_ventas: 'pos',
      point_of_sale: 'pos',
    };
    return aliases[normalized] ?? normalized;
  }

  private defaultTemplateTitle(type: TemplateTypeCode) {
    switch (type) {
      case 'herramientas':
        return 'Herramientas';
      case 'productos':
        return 'Productos';
      case 'instalacion':
        return 'Instalación';
    }
  }

  private normalizeTemplateType(raw: string): TemplateTypeCode {
    const normalized = this.normalizeCode(raw);
    if (
      normalized !== 'herramientas' &&
      normalized !== 'productos' &&
      normalized !== 'instalacion'
    ) {
      throw new BadRequestException('Tipo de checklist inválido');
    }
    return normalized;
  }

  private toTemplateTypeDbValue(type: TemplateTypeCode) {
    switch (type) {
      case 'herramientas':
        return 'HERRAMIENTAS';
      case 'productos':
        return 'PRODUCTOS';
      case 'instalacion':
        return 'INSTALACION';
    }
  }

  private fromTemplateTypeDbValue(value: string | null | undefined): TemplateTypeCode {
    const normalized = this.normalizeCode((value ?? '').toString());
    if (
      normalized === 'herramientas' ||
      normalized === 'productos' ||
      normalized === 'instalacion'
    ) {
      return normalized;
    }
    return 'instalacion';
  }

  private phaseCodeFromServicePhase(raw: string | null | undefined) {
    const normalized = this.normalizeCode((raw ?? '').toString());
    const aliases: Record<string, string> = {
      survey: 'levantamiento',
      levantamiento_tecnico: 'levantamiento',
      installation: 'instalacion',
      install: 'instalacion',
      maintenance: 'mantenimiento',
      warranty: 'garantia',
      reservation: 'reserva',
      reserve: 'reserva',
      booked: 'reserva',
    };
    return aliases[normalized] ?? normalized;
  }

  private phaseCodeFromOrderType(raw: string | null | undefined) {
    const normalized = this.normalizeCode((raw ?? '').toString());
    switch (normalized) {
      case 'instalacion':
      case 'installation':
        return 'instalacion';
      case 'mantenimiento':
      case 'servicio':
      case 'maintenance':
        return 'mantenimiento';
      case 'levantamiento':
      case 'survey':
        return 'levantamiento';
      case 'garantia':
      case 'warranty':
        return 'garantia';
      case 'reserva':
      case 'reservation':
        return 'reserva';
      default:
        return '';
    }
  }

  private resolveChecklistPhaseCodeForService(service: {
    currentPhase?: string | null;
    orderType?: string | null;
  }) {
    const phaseFromCurrent = this.phaseCodeFromServicePhase(service.currentPhase);
    if (phaseFromCurrent.length > 0 && phaseFromCurrent != 'reserva') {
      return phaseFromCurrent;
    }

    const phaseFromOrderType = this.phaseCodeFromOrderType(service.orderType);
    if (phaseFromOrderType.length > 0) {
      return phaseFromOrderType;
    }

    return phaseFromCurrent;
  }

  private async syncOperationsMetadata() {
    for (const phase of this.operationPhases) {
      await this.prisma.$executeRaw(Prisma.sql`
        INSERT INTO service_phases (id, name, code, order_index, created_at, updated_at)
        VALUES (gen_random_uuid(), ${phase.name}, ${phase.code}, ${phase.orderIndex}, now(), now())
        ON CONFLICT (code)
        DO UPDATE SET
          name = EXCLUDED.name,
          order_index = EXCLUDED.order_index,
          updated_at = now()
      `);
    }

    for (const category of this.defaultCategories) {
      await this.prisma.$executeRaw(Prisma.sql`
        INSERT INTO service_categories (id, name, code, created_at, updated_at)
        VALUES (gen_random_uuid(), ${category.name}, ${category.code}, now(), now())
        ON CONFLICT (code)
        DO UPDATE SET
          name = EXCLUDED.name,
          updated_at = now()
      `);
    }

    await this.prisma.$executeRaw(Prisma.sql`
      WITH distinct_categories AS (
        SELECT DISTINCT trim(category) AS name
        FROM "Service"
        WHERE trim(category) <> ''
      )
      INSERT INTO service_categories (id, name, code, created_at, updated_at)
      SELECT
        gen_random_uuid(),
        dc.name,
        lower(
          regexp_replace(
            regexp_replace(
              translate(
                dc.name,
                'ÁÀÄÂáàäâÉÈËÊéèëêÍÌÏÎíìïîÓÒÖÔóòöôÚÙÜÛúùüûÑñ',
                'AAAAaaaaEEEEeeeeIIIIiiiiOOOOooooUUUUuuuuNn'
              ),
              '[^a-zA-Z0-9]+',
              '_',
              'g'
            ),
            '(^_+|_+$)',
            '',
            'g'
          )
        ),
        now(),
        now()
      FROM distinct_categories dc
      ON CONFLICT (code)
      DO UPDATE SET
        name = EXCLUDED.name,
        updated_at = now()
    `);
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

  private async resolveCategoryId(dto: CreateServiceChecklistTemplateDto) {
    const categoryId = (dto.categoryId ?? '').trim();
    if (categoryId) {
      await this.findCategoryOrFail(categoryId);
      return categoryId;
    }

    const categoryCode = this.normalizeCode((dto.categoryCode ?? '').toString());
    if (!categoryCode) {
      throw new BadRequestException('La categoría del checklist es requerida');
    }

    const rows = await this.prisma.$queryRaw<Array<{ id: string }>>(
      Prisma.sql`SELECT id FROM service_categories WHERE code = ${categoryCode} LIMIT 1`,
    );
    if (rows.length === 0) {
      throw new NotFoundException('Categoría de checklist no encontrada');
    }
    return rows[0].id;
  }

  private async resolvePhaseId(dto: CreateServiceChecklistTemplateDto) {
    const phaseId = (dto.phaseId ?? '').trim();
    if (phaseId) {
      await this.findPhaseOrFail(phaseId);
      return phaseId;
    }

    const phaseCode = this.normalizeCode((dto.phaseCode ?? '').toString());
    if (!phaseCode) {
      throw new BadRequestException('La fase del checklist es requerida');
    }

    const rows = await this.prisma.$queryRaw<Array<{ id: string }>>(
      Prisma.sql`SELECT id FROM service_phases WHERE code = ${phaseCode} LIMIT 1`,
    );
    if (rows.length === 0) {
      throw new NotFoundException('Fase de checklist no encontrada');
    }
    return rows[0].id;
  }

  async listCategories() {
    await this.syncOperationsMetadata();
    const cached = await this.redis.get<LookupRow[]>(CHECKLIST_CATEGORIES_CACHE_KEY);
    if (cached) {
      if (this.redis.isEnabled()) this.logger.log(`Redis HIT ${CHECKLIST_CATEGORIES_CACHE_KEY}`);
      return cached;
    }
    if (this.redis.isEnabled()) this.logger.log(`Redis MISS ${CHECKLIST_CATEGORIES_CACHE_KEY}`);

    const rows = await this.prisma.$queryRaw<LookupRow[]>(Prisma.sql`
      SELECT
        id,
        name,
        code,
        created_at AS "createdAt",
        updated_at AS "updatedAt"
      FROM service_categories
      ORDER BY name ASC
    `);
    await this.redis.set(CHECKLIST_CATEGORIES_CACHE_KEY, rows);
    return rows;
  }

  async listPhases() {
    await this.syncOperationsMetadata();
    const cached = await this.redis.get<LookupRow[]>(CHECKLIST_PHASES_CACHE_KEY);
    if (cached) {
      if (this.redis.isEnabled()) this.logger.log(`Redis HIT ${CHECKLIST_PHASES_CACHE_KEY}`);
      return cached;
    }
    if (this.redis.isEnabled()) this.logger.log(`Redis MISS ${CHECKLIST_PHASES_CACHE_KEY}`);

    const rows = await this.prisma.$queryRaw<LookupRow[]>(Prisma.sql`
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
    await this.redis.set(CHECKLIST_PHASES_CACHE_KEY, rows);
    return rows;
  }

  async createTemplate(user: AuthUser, dto: CreateServiceChecklistTemplateDto) {
    this.assertAdmin(user);
    await this.syncOperationsMetadata();
    const [categoryId, phaseId] = await Promise.all([
      this.resolveCategoryId(dto),
      this.resolvePhaseId(dto),
    ]);

    const type = this.normalizeTemplateType(dto.type);
    const title = (dto.title?.trim().length ?? 0) > 0
      ? dto.title!.trim()
      : this.defaultTemplateTitle(type);
    const rows = await this.prisma.$queryRaw<
      Array<{
        id: string;
        type: string;
        title: string;
        categoryId: string;
        phaseId: string;
        createdAt: Date;
        updatedAt: Date;
      }>
    >(Prisma.sql`
      INSERT INTO checklist_templates (id, category_id, phase_id, type, title, created_at, updated_at)
      VALUES (
        gen_random_uuid(),
        ${categoryId}::uuid,
        ${phaseId}::uuid,
        ${this.toTemplateTypeDbValue(type)}::"ChecklistTemplateType",
        ${title},
        now(),
        now()
      )
      ON CONFLICT (category_id, phase_id, type)
      DO UPDATE SET
        title = EXCLUDED.title,
        updated_at = now()
      RETURNING
        id,
        type,
        title,
        category_id AS "categoryId",
        phase_id AS "phaseId",
        created_at AS "createdAt",
        updated_at AS "updatedAt"
    `);
      await this.invalidateChecklistCache('checklist.createTemplate');
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
      await this.invalidateChecklistCache('checklist.createItem');
    return rows[0];
  }

  async listTemplates(filters?: {
    categoryId?: string;
    phaseId?: string;
    categoryCode?: string;
    phaseCode?: string;
  }) {
    await this.syncOperationsMetadata();
    const cacheKey = this.buildTemplateCacheKey(filters);
    const cached = await this.redis.get<any[]>(cacheKey);
    if (cached) {
      if (this.redis.isEnabled()) this.logger.log(`Redis HIT ${cacheKey}`);
      return cached;
    }
    if (this.redis.isEnabled()) this.logger.log(`Redis MISS ${cacheKey}`);

    const where: Prisma.Sql[] = [];
    const categoryId = filters?.categoryId?.trim() ?? '';
    const phaseId = filters?.phaseId?.trim() ?? '';
    const categoryCode = this.normalizeCode(filters?.categoryCode ?? '');
    const phaseCode = this.normalizeCode(filters?.phaseCode ?? '');

    if (categoryId.length > 0) {
      where.push(
        Prisma.sql`ct.category_id = ${categoryId}::uuid`,
      );
    }
    if (categoryCode.length > 0) {
      where.push(Prisma.sql`sc.code = ${categoryCode}`);
    }
    if (phaseId.length > 0) {
      where.push(Prisma.sql`ct.phase_id = ${phaseId}::uuid`);
    }
    if (phaseCode.length > 0) {
      where.push(Prisma.sql`sp.code = ${phaseCode}`);
    }

    const predicate = where.length === 0
      ? Prisma.empty
      : Prisma.sql`WHERE ${Prisma.join(where, ' AND ')}`;

    const rows = await this.prisma.$queryRaw<TemplateListRow[]>(Prisma.sql`
      SELECT
        ct.id AS "templateId",
        ct.type::text AS type,
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
      ORDER BY
        sp.order_index ASC,
        sp.name ASC,
        CASE ct.type
          WHEN 'HERRAMIENTAS' THEN 1
          WHEN 'PRODUCTOS' THEN 2
          ELSE 3
        END ASC,
        ct.title ASC,
        ci.order_index ASC,
        ci.label ASC
    `);
    const grouped = this.groupTemplateRows(rows);
    await this.redis.set(cacheKey, grouped);
    return grouped;
  }

  async ensureServiceChecklists(service: {
    id: string;
    category?: string | null;
    currentPhase?: string | null;
    orderType?: string | null;
  }) {
    const serviceId = service.id.trim();
    const categoryCode = this.canonicalChecklistCategoryCode((service.category ?? '').toString());
    const phaseCode = this.resolveChecklistPhaseCodeForService(service);
    if (!serviceId || !categoryCode || !phaseCode) return;
    await this.syncOperationsMetadata();
    await this.ensureServiceChecklistsWithClient(
      this.prisma,
      serviceId,
      categoryCode,
      phaseCode,
    );
  }

  private async ensureServiceChecklistsWithClient(
    db: SqlClient,
    serviceId: string,
    categoryCode: string,
    phaseCode: string,
  ) {
    await db.$executeRaw(Prisma.sql`
      INSERT INTO checklist_executions (
        id,
        service_order_id,
        template_id,
        checklist_item_id,
        is_checked,
        checked_at,
        checked_by,
        created_at,
        updated_at
      )
      SELECT
        gen_random_uuid(),
        ${serviceId}::uuid,
        ct.id,
        ci.id,
        false,
        NULL,
        NULL,
        now(),
        now()
      FROM checklist_templates ct
      INNER JOIN service_categories sc ON sc.id = ct.category_id
      INNER JOIN service_phases sp ON sp.id = ct.phase_id
      INNER JOIN checklist_items ci ON ci.template_id = ct.id
      LEFT JOIN checklist_executions ce
        ON ce.service_order_id = ${serviceId}::uuid
       AND ce.checklist_item_id = ci.id
      WHERE sc.code = ${categoryCode}
        AND sp.code = ${phaseCode}
        AND ce.id IS NULL
    `);
  }

  async getServiceChecklists(user: AuthUser, serviceId: string) {
    const service = await this.operations.findOne(user, serviceId);
    const cacheKey = this.buildServiceChecklistCacheKey(service);
    const cached = await this.redis.get<any>(cacheKey);
    if (cached) {
      if (this.redis.isEnabled()) this.logger.log(`Redis HIT ${cacheKey}`);
      return cached;
    }
    if (this.redis.isEnabled()) this.logger.log(`Redis MISS ${cacheKey}`);

    const categoryCode = this.canonicalChecklistCategoryCode((service.category ?? '').toString());
    const phaseCode = this.resolveChecklistPhaseCodeForService(service);

    await this.ensureServiceChecklists({
      id: service.id,
      category: service.category,
      currentPhase: service.currentPhase,
      orderType: service.orderType,
    });

    const rows = await this.prisma.$queryRaw<ChecklistExecutionRow[]>(Prisma.sql`
      SELECT
        ce.id AS "executionId",
        ct.id AS "templateId",
        ct.type::text AS type,
        ct.title,
        sc.id AS "categoryId",
        sc.name AS "categoryName",
        sc.code AS "categoryCode",
        sp.id AS "phaseId",
        sp.name AS "phaseName",
        sp.code AS "phaseCode",
        sp.order_index AS "phaseOrderIndex",
        ci.id AS "checklistItemId",
        ci.label AS "itemLabel",
        ci.is_required AS "itemRequired",
        ci.order_index AS "itemOrderIndex",
        ce.is_checked AS "isChecked",
        ce.checked_at AS "checkedAt",
        ce.checked_by AS "checkedById",
        u."nombreCompleto" AS "checkedByName"
      FROM checklist_executions ce
      INNER JOIN checklist_templates ct ON ct.id = ce.template_id
      INNER JOIN service_categories sc ON sc.id = ct.category_id
      INNER JOIN service_phases sp ON sp.id = ct.phase_id
      INNER JOIN checklist_items ci ON ci.id = ce.checklist_item_id
      LEFT JOIN "users" u ON u.id = ce.checked_by
      WHERE ce.service_order_id = ${serviceId}::uuid
        AND sc.code = ${categoryCode}
        AND sp.code = ${phaseCode}
      ORDER BY
        CASE ct.type
          WHEN 'HERRAMIENTAS' THEN 1
          WHEN 'PRODUCTOS' THEN 2
          ELSE 3
        END ASC,
        ci.order_index ASC,
        ci.label ASC
    `);

    const templates = this.groupExecutionRows(rows);
    const response = {
      serviceId: service.id,
      currentPhase: phaseCode,
      orderState: service.orderState,
      category: {
        code: categoryCode,
        label: (service.category ?? '').toString(),
      },
      sections: this.groupTemplatesByType(templates),
      templates,
    };
    await this.redis.set(cacheKey, response);
    return response;
  }

  async checkServiceChecklistItem(
    user: AuthUser,
    executionId: string,
    dto: CheckServiceChecklistItemDto,
  ) {
    const rows = await this.prisma.$queryRaw<ChecklistExecutionLookupRow[]>(
      Prisma.sql`
        SELECT
          ce.id AS "executionId",
          ce.service_order_id AS "serviceId"
        FROM checklist_executions ce
        WHERE ce.id = ${executionId}::uuid
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
      UPDATE checklist_executions
      SET
        is_checked = ${dto.isChecked},
        checked_at = ${checkedAt},
        checked_by = ${checkedById},
        updated_at = now()
      WHERE id = ${executionId}::uuid
      RETURNING
        id,
        is_checked AS "isChecked",
        checked_at AS "checkedAt",
        checked_by AS "checkedById"
    `);
      await this.invalidateChecklistCache('checklist.checkItem', row.serviceId);
    return updatedRows[0];
  }

  private groupTemplateRows(rows: TemplateListRow[]) {
    const templates = new Map<string, any>();

    for (const row of rows) {
      let current = templates.get(row.templateId);
      if (!current) {
        current = {
          id: row.templateId,
          templateId: row.templateId,
          type: this.fromTemplateTypeDbValue(row.type),
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
          checklistItemId: row.itemId,
          label: row.itemLabel ?? '',
          isRequired: row.itemRequired ?? true,
          orderIndex: row.itemOrderIndex ?? 0,
          isChecked: false,
          checkedAt: null,
          checkedByUserId: null,
          checkedByName: null,
        });
      }
    }

    return Array.from(templates.values());
  }

  private groupExecutionRows(rows: ChecklistExecutionRow[]) {
    const templates = new Map<string, any>();

    for (const row of rows) {
      let current = templates.get(row.templateId);
      if (!current) {
        current = {
          id: row.templateId,
          templateId: row.templateId,
          type: this.fromTemplateTypeDbValue(row.type),
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

      if (row.executionId && row.checklistItemId) {
        current.items.push({
          id: row.executionId,
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

  private groupTemplatesByType(templates: any[]) {
    return {
      herramientas: templates.filter((template) => template.type == 'herramientas'),
      productos: templates.filter((template) => template.type == 'productos'),
      instalacion: templates.filter((template) => template.type == 'instalacion'),
    };
  }
}
