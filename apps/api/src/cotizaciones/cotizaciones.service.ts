import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { CompanyManualAudience, CompanyManualEntryKind, Prisma, Role } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { AnalyzeCotizacionAiDto } from './dto/analyze-cotizacion-ai.dto';
import { ChatCotizacionAiDto } from './dto/chat-cotizacion-ai.dto';
import { CreateCotizacionDto, CreateCotizacionItemDto } from './dto/create-cotizacion.dto';
import { UpdateCotizacionDto } from './dto/update-cotizacion.dto';

type AiRuntimeConfig = {
  apiKey: string;
  model: string;
  companyName: string;
};

type BusinessRuleRecord = {
  id: string;
  module: string;
  category: string;
  title: string;
  content: string;
  summary: string | null;
  keywords: string[];
  severity: 'info' | 'warning' | 'critical';
  active: boolean;
  createdAt: string | null;
  updatedAt: string | null;
};

@Injectable()
export class CotizacionesService {
  private readonly logger = new Logger(CotizacionesService.name);
  private static readonly noRuleMessage =
    'No encontré una regla oficial para eso dentro del sistema.';
  private static readonly rulesOnlyReminder =
    'Solo puedo responder con base en reglas oficiales del Manual Interno.';

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  async list(user: { id: string; role: Role }, query: { customerPhone?: string; take?: number }) {
    const take = Math.min(Math.max(query.take ?? 80, 1), 500);
    const where: Prisma.CotizacionWhereInput = {};

    const customerPhone = query.customerPhone?.trim();
    if (customerPhone) where.customerPhone = customerPhone;

    // Non-admin users only see their own cotizaciones.
    if (user.role !== Role.ADMIN) {
      where.createdByUserId = user.id;
    }

    const items = await this.prisma.cotizacion.findMany({
      where,
      take,
      orderBy: { createdAt: 'desc' },
      include: { items: { orderBy: { createdAt: 'asc' } } },
    });

    return { items };
  }

  async findOne(user: { id: string; role: Role }, id: string) {
    const item = await this.prisma.cotizacion.findUnique({
      where: { id },
      include: { items: { orderBy: { createdAt: 'asc' } } },
    });

    if (!item) throw new NotFoundException('Cotización no encontrada');

    if (user.role !== Role.ADMIN && item.createdByUserId !== user.id) {
      throw new ForbiddenException('No puedes ver esta cotización');
    }

    return item;
  }

  async create(user: { id: string; role: Role }, dto: CreateCotizacionDto) {
    if (!dto.items?.length) {
      throw new BadRequestException('Agrega al menos un producto al ticket');
    }

    const customerPhone = dto.customerPhone.trim();
    const customerName = dto.customerName.trim();
    const note = (dto.note ?? '').trim();

    if (!customerPhone) throw new BadRequestException('Teléfono requerido');
    if (!customerName) throw new BadRequestException('Nombre de cliente requerido');

    const includeItbis = dto.includeItbis === true;
    const itbisRateRaw = dto.itbisRate ?? 0.18;
    const itbisRate = new Prisma.Decimal(Math.max(0, Math.min(itbisRateRaw, 1)));

    const normalized = await this.normalizeItems(dto.items);

    let subtotal = new Prisma.Decimal(0);
    for (const line of normalized) subtotal = subtotal.plus(line.lineTotal);

    const itbisAmount = includeItbis ? subtotal.mul(itbisRate) : new Prisma.Decimal(0);
    const total = subtotal.plus(itbisAmount);

    return this.prisma.$transaction(async (tx) => {
      const created = await tx.cotizacion.create({
        data: {
          createdByUserId: user.id,
          customerId: dto.customerId,
          customerName,
          customerPhone,
          note: note.length ? note : null,
          includeItbis,
          itbisRate,
          subtotal,
          itbisAmount,
          total,
          items: {
            create: normalized.map((item) => ({
              productId: item.productId,
              productNameSnapshot: item.productNameSnapshot,
              productImageSnapshot: item.productImageSnapshot,
              qty: item.qty,
              unitPrice: item.unitPrice,
              lineTotal: item.lineTotal,
            })),
          },
        },
        include: { items: { orderBy: { createdAt: 'asc' } } },
      });

      return created;
    });
  }

  async update(user: { id: string; role: Role }, id: string, dto: UpdateCotizacionDto) {
    const current = await this.prisma.cotizacion.findUnique({ where: { id } });
    if (!current) throw new NotFoundException('Cotización no encontrada');

    if (user.role !== Role.ADMIN && current.createdByUserId !== user.id) {
      throw new ForbiddenException('No puedes editar esta cotización');
    }

    const includeItbis = dto.includeItbis ?? current.includeItbis;
    const itbisRateRaw = dto.itbisRate ?? this.toNumber(current.itbisRate);
    const itbisRate = new Prisma.Decimal(Math.max(0, Math.min(itbisRateRaw, 1)));

    const nextItems = dto.items ? await this.normalizeItems(dto.items as CreateCotizacionItemDto[]) : null;

    let subtotal = new Prisma.Decimal(current.subtotal);
    let itbisAmount = new Prisma.Decimal(current.itbisAmount);
    let total = new Prisma.Decimal(current.total);

    if (nextItems) {
      subtotal = new Prisma.Decimal(0);
      for (const line of nextItems) subtotal = subtotal.plus(line.lineTotal);
      itbisAmount = includeItbis ? subtotal.mul(itbisRate) : new Prisma.Decimal(0);
      total = subtotal.plus(itbisAmount);
    }

    return this.prisma.$transaction(async (tx) => {
      if (nextItems) {
        await tx.cotizacionItem.deleteMany({ where: { cotizacionId: id } });
      }

      const updated = await tx.cotizacion.update({
        where: { id },
        data: {
          customerId: dto.customerId ?? current.customerId,
          customerName: dto.customerName ? dto.customerName.trim() : current.customerName,
          customerPhone: dto.customerPhone ? dto.customerPhone.trim() : current.customerPhone,
          note: dto.note !== undefined ? (dto.note?.trim().length ? dto.note.trim() : null) : current.note,
          includeItbis,
          itbisRate,
          subtotal,
          itbisAmount,
          total,
          items: nextItems
            ? {
                create: nextItems.map((item) => ({
                  productId: item.productId,
                  productNameSnapshot: item.productNameSnapshot,
                  productImageSnapshot: item.productImageSnapshot,
                  qty: item.qty,
                  unitPrice: item.unitPrice,
                  lineTotal: item.lineTotal,
                })),
              }
            : undefined,
        },
        include: { items: { orderBy: { createdAt: 'asc' } } },
      });

      return updated;
    });
  }

  async remove(user: { id: string; role: Role }, id: string) {
    const current = await this.prisma.cotizacion.findUnique({ where: { id } });
    if (!current) throw new NotFoundException('Cotización no encontrada');

    if (user.role !== Role.ADMIN && current.createdByUserId !== user.id) {
      throw new ForbiddenException('No puedes eliminar esta cotización');
    }

    await this.prisma.cotizacion.delete({ where: { id } });
    return { ok: true };
  }

  async analyzeAssistant(
    user: { id: string; role: Role },
    dto: AnalyzeCotizacionAiDto,
  ) {
    const rules = await this.loadRelevantBusinessRules(user, dto.context, dto.instruction);
    this.logDebug('analyze.context', dto.context);
    this.logDebug('analyze.rules', rules.map((item) => ({ id: item.id, title: item.title })));

    if (rules.length === 0) {
      return {
        source: 'rules-only',
        summary: CotizacionesService.noRuleMessage,
        warnings: [],
        relatedRules: [],
      };
    }

    const runtime = await this.getOpenAiRuntimeConfig();
    if (!runtime.apiKey) {
      return {
        source: 'rules-only',
        summary:
          'Se cargaron reglas oficiales relacionadas, pero la IA avanzada no está configurada. Las validaciones locales deben seguir utilizándose.',
        warnings: [],
        relatedRules: rules.map((item) => this.toRuleReference(item)),
      };
    }

    const promptPayload = {
      instruction: dto.instruction?.trim() || 'Revisa esta cotización con base en las reglas oficiales.',
      context: dto.context,
      rules,
    };

    const parsed = await this.requestStrictJsonFromOpenAi<{
      summary?: unknown;
      warnings?: unknown;
      relatedRuleIds?: unknown;
    }>({
      runtime,
      temperature: 0.1,
      systemPrompt:
        'Eres el asistente interno de FULLTECH dentro del módulo de cotización. Solo puedes responder usando las reglas oficiales proporcionadas por el sistema. No inventes precios, no supongas condiciones, no uses conocimiento externo. Si una respuesta no está definida en las reglas disponibles, debes decir claramente que no encontraste una regla oficial. Tu función es ayudar al vendedor, validar cotizaciones y advertir sobre posibles inconsistencias sin bloquear el flujo de trabajo. Siempre que menciones una regla, intenta devolver el identificador o título de la regla relacionada. Responde únicamente JSON válido.',
      userPrompt:
        `${JSON.stringify(promptPayload)}\n\nDevuelve exactamente este JSON: {"summary":"string","warnings":[{"title":"string","description":"string","type":"info|warning|success","relatedRuleId":"string|null","relatedRuleTitle":"string|null","suggestedAction":"string|null"}],"relatedRuleIds":["string"]}. Si las reglas no cubren el caso, usa como summary exactamente: "${CotizacionesService.noRuleMessage}" y devuelve warnings vacíos.`,
    });

    const relatedRules = this.pickRelatedRules(rules, parsed.relatedRuleIds);
    const warnings = this.normalizeAiWarnings(parsed.warnings, rules);

    this.logDebug('analyze.warnings', warnings);

    return {
      source: 'openai',
      summary:
        this.normalizeOptionalString(parsed.summary) ??
        (warnings.length > 0
            ? 'Se detectaron advertencias basadas en las reglas oficiales.'
            : 'La cotización parece correcta según las reglas actuales.'),
      warnings,
      relatedRules,
    };
  }

  async chatAssistant(user: { id: string; role: Role }, dto: ChatCotizacionAiDto) {
    const message = dto.message.trim();
    if (!message) {
      throw new BadRequestException('El mensaje es obligatorio');
    }

    const rules = await this.loadRelevantBusinessRules(user, dto.context, message);
    this.logDebug('chat.context', dto.context);
    this.logDebug('chat.rules', rules.map((item) => ({ id: item.id, title: item.title })));

    if (rules.length === 0) {
      return {
        source: 'rules-only',
        content: CotizacionesService.noRuleMessage,
        relatedRuleId: null,
        relatedRuleTitle: null,
        citations: [],
      };
    }

    const runtime = await this.getOpenAiRuntimeConfig();
    if (!runtime.apiKey) {
      return this.buildRuleOnlyChatFallback(message, rules);
    }

    const parsed = await this.requestStrictJsonFromOpenAi<{
      content?: unknown;
      relatedRuleId?: unknown;
      relatedRuleTitle?: unknown;
      citations?: unknown;
      unsupported?: unknown;
    }>({
      runtime,
      temperature: 0,
      systemPrompt:
        'Eres el asistente interno de FULLTECH dentro del módulo de cotización. Debes responder 100% con base en las reglas oficiales del Manual Interno enviadas en la solicitud. No inventes precios, no resumas conocimiento externo, no completes huecos con supuestos y no des consejos no sustentados por una regla enviada. Toda respuesta útil debe quedar apoyada por al menos una regla citada de las proporcionadas. Si la pregunta no está cubierta por las reglas disponibles, debes responder exactamente que no encontraste una regla oficial. Si el usuario solo saluda o escribe algo ambiguo, responde de forma breve recordando que solo trabajas con reglas oficiales y pidiéndole una pregunta concreta sobre políticas, precios, garantía, DVR, instalación u otra regla del manual. Responde únicamente JSON válido.',
      userPrompt:
        `${JSON.stringify({ message, context: dto.context, rules })}\n\nDevuelve exactamente este JSON: {"content":"string","relatedRuleId":"string|null","relatedRuleTitle":"string|null","citations":[{"id":"string","title":"string"}],"unsupported":false}. Reglas estrictas: 1) si respondes algo util, citations no puede ir vacio; 2) relatedRuleId o relatedRuleTitle debe apuntar a una regla enviada; 3) no agregues nada que no pueda leerse o inferirse directamente de las reglas; 4) si la pregunta no esta cubierta, usa exactamente este texto en content: "${CotizacionesService.noRuleMessage}" y usa unsupported=true; 5) si el mensaje es ambiguo o solo social, usa exactamente este texto en content: "${CotizacionesService.rulesOnlyReminder}" y usa unsupported=true.`,
    });

    const relatedRule = rules.find((item) => item.id === this.normalizeOptionalString(parsed.relatedRuleId));
    const citations = this.normalizeCitations(parsed.citations, rules);
    const content = this.normalizeOptionalString(parsed.content) ?? CotizacionesService.noRuleMessage;

    const unsupported = parsed.unsupported === true;
    const relatedRuleId = relatedRule?.id ?? this.normalizeOptionalString(parsed.relatedRuleId);
    const relatedRuleTitle = relatedRule?.title ?? this.normalizeOptionalString(parsed.relatedRuleTitle);

    if (content === CotizacionesService.rulesOnlyReminder) {
      return {
        source: 'rules-only',
        content,
        relatedRuleId: null,
        relatedRuleTitle: null,
        citations: [],
      };
    }

    if (unsupported || content === CotizacionesService.noRuleMessage) {
      return this.buildRuleOnlyChatFallback(message, rules);
    }

    if (citations.length === 0 && !relatedRuleId && !relatedRuleTitle) {
      return this.buildRuleOnlyChatFallback(message, rules);
    }

    return {
      source: 'openai',
      content,
      relatedRuleId,
      relatedRuleTitle,
      citations,
    };
  }

  private async normalizeItems(items: CreateCotizacionItemDto[]) {
    const productIds = Array.from(new Set(items.map((i) => i.productId).filter((id): id is string => Boolean(id))));

    let products: Array<{ id: string; nombre: string; imagen: string | null }> = [];
    if (productIds.length) {
      products = await this.prisma.product.findMany({
        where: { id: { in: productIds } },
        select: { id: true, nombre: true, imagen: true },
      });
    }

    const productMap = new Map(products.map((p) => [p.id, p]));

    return items.map((item, index) => {
      const qty = new Prisma.Decimal(item.qty);
      const unitPrice = new Prisma.Decimal(item.unitPrice);

      if (qty.lte(0)) throw new BadRequestException(`Cantidad inválida en item #${index + 1}`);
      if (unitPrice.lt(0)) throw new BadRequestException(`Precio inválido en item #${index + 1}`);

      const productId = item.productId ?? null;
      const product = productId ? productMap.get(productId) : null;

      const productNameSnapshot = product?.nombre ?? item.productName?.trim();
      if (!productNameSnapshot) {
        throw new BadRequestException(`Nombre requerido en item #${index + 1}`);
      }

      const productImageSnapshot = product?.imagen ?? item.productImageSnapshot ?? null;
      const lineTotal = qty.mul(unitPrice);

      return {
        productId: product?.id ?? productId,
        productNameSnapshot,
        productImageSnapshot,
        qty,
        unitPrice,
        lineTotal,
      };
    });
  }

  private toNumber(value: Prisma.Decimal | number | string | null | undefined): number {
    if (value === null || value === undefined) return 0;
    if (typeof value === 'number') return value;
    return Number(value);
  }

  private async resolveCompanyOwnerId(fallbackUserId: string) {
    const admin = await this.prisma.user.findFirst({
      where: { role: Role.ADMIN },
      orderBy: { createdAt: 'asc' },
      select: { id: true },
    });
    return admin?.id ?? fallbackUserId;
  }

  private async getOpenAiRuntimeConfig(): Promise<AiRuntimeConfig> {
    const envKey = (this.config.get<string>('OPENAI_API_KEY') ?? process.env.OPENAI_API_KEY ?? '').trim();
    const envModel = (this.config.get<string>('OPENAI_MODEL') ?? process.env.OPENAI_MODEL ?? '').trim();

    let appConfig:
      | { openAiApiKey: string | null; openAiModel: string | null; companyName: string | null }
      | null = null;

    try {
      appConfig = await this.prisma.appConfig.findUnique({
        where: { id: 'global' },
        select: { openAiApiKey: true, openAiModel: true, companyName: true },
      });
    } catch {
      appConfig = null;
    }

    return {
      apiKey: envKey.length > 0 ? envKey : (appConfig?.openAiApiKey ?? '').trim(),
      model:
        envModel.length > 0
          ? envModel
          : ((appConfig?.openAiModel ?? '').trim() || 'gpt-4o-mini'),
      companyName: (appConfig?.companyName ?? 'FULLTECH').trim() || 'FULLTECH',
    };
  }

  private getOpenAiModelCandidates(preferredModel: string) {
    const autoCandidatesEnv = (process.env.OPENAI_MODEL_CANDIDATES ?? '').trim();
    const autoCandidates = autoCandidatesEnv.length > 0
      ? autoCandidatesEnv
          .split(',')
          .map((item) => item.trim())
          .filter((item) => item.length > 0)
      : ['gpt-5', 'gpt-4.1', 'gpt-4o', 'gpt-4o-mini'];

    return [preferredModel, ...autoCandidates].filter(
      (value, index, list) => value.length > 0 && list.indexOf(value) === index,
    );
  }

  private extractJsonObject(raw: string) {
    const trimmed = raw.trim();
    const fenced = trimmed.startsWith('```')
      ? trimmed.replace(/^```(?:json)?\s*/i, '').replace(/```$/i, '').trim()
      : trimmed;
    const firstBrace = fenced.indexOf('{');
    const lastBrace = fenced.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      return fenced.slice(firstBrace, lastBrace + 1);
    }
    return fenced;
  }

  private async requestStrictJsonFromOpenAi<T>({
    runtime,
    systemPrompt,
    userPrompt,
    temperature,
  }: {
    runtime: AiRuntimeConfig;
    systemPrompt: string;
    userPrompt: string;
    temperature: number;
  }): Promise<T> {
    const modelCandidates = this.getOpenAiModelCandidates(runtime.model);

    for (const candidate of modelCandidates) {
      try {
        const response = await fetch('https://api.openai.com/v1/chat/completions', {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${runtime.apiKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            model: candidate,
            temperature,
            messages: [
              { role: 'system', content: systemPrompt },
              { role: 'user', content: userPrompt },
            ],
          }),
        });

        if (!response.ok) {
          this.logDebug('openai.http_error', { candidate, status: response.status });
          continue;
        }

        const payload = (await response.json()) as {
          choices?: Array<{ message?: { content?: string } }>;
        };
        const content = payload.choices?.[0]?.message?.content?.trim();
        if (!content) continue;

        return JSON.parse(this.extractJsonObject(content)) as T;
      } catch (error) {
        this.logDebug('openai.parse_error', {
          candidate,
          message: error instanceof Error ? error.message : `${error}`,
        });
      }
    }

    throw new BadRequestException('No se pudo generar una respuesta válida desde OpenAI para cotizaciones.');
  }

  private async loadRelevantBusinessRules(
    user: { id: string; role: Role },
    context: AnalyzeCotizacionAiDto['context'],
    prompt?: string,
  ) {
    const ownerId = await this.resolveCompanyOwnerId(user.id);
    const where: Prisma.CompanyManualEntryWhereInput = {
      ownerId,
      published: true,
      kind: {
        in: [
          CompanyManualEntryKind.GENERAL_RULE,
          CompanyManualEntryKind.ROLE_RULE,
          CompanyManualEntryKind.POLICY,
          CompanyManualEntryKind.WARRANTY_POLICY,
          CompanyManualEntryKind.RESPONSIBILITY,
          CompanyManualEntryKind.PRICE_RULE,
          CompanyManualEntryKind.SERVICE_RULE,
          CompanyManualEntryKind.PRODUCT_SERVICE,
          CompanyManualEntryKind.MODULE_GUIDE,
        ],
      },
      OR: [
        { audience: CompanyManualAudience.GENERAL },
        {
          audience: CompanyManualAudience.ROLE_SPECIFIC,
          targetRoles: { has: user.role },
        },
      ],
    };

    const entries = await this.prisma.companyManualEntry.findMany({
      where,
      orderBy: [{ sortOrder: 'asc' }, { updatedAt: 'desc' }, { title: 'asc' }],
    });

    const desiredModuleKeys = new Set(
      [
        (context.module ?? '').trim().toLowerCase(),
        'cotizaciones',
        'cotizacion',
        'ventas',
        'manual-interno',
      ].filter((item) => item.length > 0),
    );

    const queryText = [
      prompt,
      context.productType,
      context.productName,
      context.brand,
      context.installationType,
      context.currentDvrType,
      context.requiredDvrType,
      context.notes,
      ...(context.components ?? []),
      ...(context.extraCharges ?? []),
      ...(context.items ?? []).flatMap((item) => [item.productName, item.category, item.notes]),
    ]
      .filter((item): item is string => typeof item === 'string' && item.trim().length > 0)
      .join(' ')
      .toLowerCase();

    const queryTokens = this.tokenize(queryText);

    const scored = entries
      .map((entry) => {
        const moduleKey = (entry.moduleKey ?? '').trim().toLowerCase();
        const text = [entry.title, entry.summary ?? '', entry.content, moduleKey]
          .join(' ')
          .toLowerCase();
        const textTokens = new Set(this.tokenize(text));

        let score = 0;
        if (!moduleKey) score += 10;
        if (desiredModuleKeys.has(moduleKey)) score += 6;
        if (moduleKey === 'cotizaciones' || moduleKey === 'cotizacion') score += 4;
        if (text.includes('precio') || text.includes('mínimo') || text.includes('minimo')) score += 2;
        if (text.includes('garant')) score += 2;
        if (text.includes('dvr') || text.includes('nvr') || text.includes('xvr')) score += 3;
        if (text.includes('cámara') || text.includes('camara')) score += 3;
        if (text.includes('instal')) score += 2;
        for (const token of queryTokens) {
          if (textTokens.has(token)) score += token.length >= 5 ? 2 : 1;
        }

        return {
          entry,
          score,
        };
      })
      .filter((item) => item.score > 0)
      .sort((left, right) => right.score - left.score)
      .slice(0, 12)
      .map(({ entry }) => this.toBusinessRuleRecord(entry));

    if (scored.length > 0) {
      return scored;
    }

    return entries.slice(0, 12).map((entry) => this.toBusinessRuleRecord(entry));
  }

  private toBusinessRuleRecord(entry: {
    id: string;
    title: string;
    summary: string | null;
    content: string;
    moduleKey: string | null;
    kind: CompanyManualEntryKind;
    published: boolean;
    createdAt: Date;
    updatedAt: Date;
  }): BusinessRuleRecord {
    return {
      id: entry.id,
      module: (entry.moduleKey ?? 'general').trim().toLowerCase() || 'general',
      category: this.mapRuleCategory(entry.kind),
      title: entry.title,
      content: entry.content,
      summary: entry.summary,
      keywords: this.tokenize([entry.title, entry.summary ?? '', entry.content].join(' ')).slice(0, 18),
      severity: this.inferSeverity(entry.kind, entry.title, entry.content),
      active: entry.published,
      createdAt: entry.createdAt?.toISOString() ?? null,
      updatedAt: entry.updatedAt?.toISOString() ?? null,
    };
  }

  private mapRuleCategory(kind: CompanyManualEntryKind) {
    switch (kind) {
      case CompanyManualEntryKind.PRICE_RULE:
        return 'precios';
      case CompanyManualEntryKind.WARRANTY_POLICY:
        return 'garantias';
      case CompanyManualEntryKind.SERVICE_RULE:
        return 'servicios';
      case CompanyManualEntryKind.PRODUCT_SERVICE:
        return 'productos';
      case CompanyManualEntryKind.MODULE_GUIDE:
        return 'modulo';
      case CompanyManualEntryKind.POLICY:
        return 'politicas';
      case CompanyManualEntryKind.GENERAL_RULE:
      case CompanyManualEntryKind.ROLE_RULE:
      case CompanyManualEntryKind.RESPONSIBILITY:
      default:
        return 'general';
    }
  }

  private inferSeverity(kind: CompanyManualEntryKind, title: string, content: string): 'info' | 'warning' | 'critical' {
    const text = `${title} ${content}`.toLowerCase();
    if (text.includes('prohib') || text.includes('no permitido') || text.includes('obligatorio')) {
      return 'critical';
    }
    if (
      kind === CompanyManualEntryKind.PRICE_RULE ||
      kind === CompanyManualEntryKind.WARRANTY_POLICY ||
      text.includes('mínimo') ||
      text.includes('minimo')
    ) {
      return 'warning';
    }
    return 'info';
  }

  private tokenize(value: string) {
    return value
      .toLowerCase()
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .split(/[^a-z0-9]+/)
      .map((item) => item.trim())
      .filter((item) => item.length >= 3);
  }

  private normalizeOptionalString(value: unknown) {
    if (typeof value !== 'string') return null;
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
  }

  private pickRelatedRules(rules: BusinessRuleRecord[], rawIds: unknown) {
    const ids = Array.isArray(rawIds)
      ? rawIds.map((item) => this.normalizeOptionalString(item)).filter((item): item is string => !!item)
      : [];
    return rules
      .filter((item) => ids.includes(item.id))
      .map((item) => this.toRuleReference(item));
  }

  private normalizeAiWarnings(rawWarnings: unknown, rules: BusinessRuleRecord[]) {
    if (!Array.isArray(rawWarnings)) return [];
    return rawWarnings
      .map((item) => {
        if (typeof item !== 'object' || item === null || Array.isArray(item)) return null;
        const row = item as Record<string, unknown>;
        const ruleId = this.normalizeOptionalString(row.relatedRuleId);
        const relatedRule = rules.find((rule) => rule.id === ruleId);
        const typeRaw = this.normalizeOptionalString(row.type) ?? 'info';
        const type = typeRaw === 'warning' || typeRaw === 'success' ? typeRaw : 'info';
        const title = this.normalizeOptionalString(row.title);
        const description = this.normalizeOptionalString(row.description);
        if (!title || !description) return null;
        return {
          title,
          description,
          type,
          relatedRuleId: relatedRule?.id ?? ruleId,
          relatedRuleTitle:
            relatedRule?.title ?? this.normalizeOptionalString(row.relatedRuleTitle),
          suggestedAction: this.normalizeOptionalString(row.suggestedAction),
        };
      })
      .filter((item): item is NonNullable<typeof item> => !!item);
  }

  private normalizeCitations(rawCitations: unknown, rules: BusinessRuleRecord[]) {
    if (!Array.isArray(rawCitations)) return [];
    return rawCitations
      .map((item) => {
        if (typeof item !== 'object' || item === null || Array.isArray(item)) return null;
        const row = item as Record<string, unknown>;
        const id = this.normalizeOptionalString(row.id);
        const rule = rules.find((entry) => entry.id === id);
        const title = rule?.title ?? this.normalizeOptionalString(row.title);
        if (!title) return null;
        return {
          id: rule?.id ?? id,
          title,
        };
      })
      .filter((item): item is NonNullable<typeof item> => !!item);
  }

  private toRuleReference(rule: BusinessRuleRecord) {
    return {
      id: rule.id,
      module: rule.module,
      category: rule.category,
      title: rule.title,
    };
  }

  private buildRuleOnlyChatFallback(message: string, rules: BusinessRuleRecord[]) {
    const normalizedMessage = message.trim().toLowerCase();
    const hasMeaningfulQuestion = this.tokenize(normalizedMessage).length > 0;
    const matchedRules = hasMeaningfulQuestion
      ? this.rankRulesForPrompt(message, rules).slice(0, 2)
      : [];
    const topRule = matchedRules[0] ?? rules[0];
    if (!topRule) {
      return {
        source: 'rules-only',
        content: CotizacionesService.noRuleMessage,
        relatedRuleId: null,
        relatedRuleTitle: null,
        citations: [],
      };
    }

    const selectedRules = matchedRules.length > 0 ? matchedRules : [topRule];
    const citations = selectedRules.map((rule) => this.toRuleReference(rule));
    const summaryParts = selectedRules
      .map((rule, index) => {
        const excerpt = this.buildExcerpt(rule.summary?.trim().length ? rule.summary : rule.content);
        const prefix = index == 0 ? `Segun la regla oficial "${rule.title}"` : `Tambien aplica "${rule.title}"`;
        return excerpt.length > 0 ? `${prefix}: ${excerpt}` : prefix;
      })
      .filter((item) => item.trim().length > 0);

    const content = summaryParts.length > 0
      ? summaryParts.join(' ')
      : `Solo puedo responder con base en reglas oficiales. La regla mas cercana es "${topRule.title}".`;

    return {
      source: 'rules-only',
      content,
      relatedRuleId: topRule.id,
      relatedRuleTitle: topRule.title,
      citations,
    };
  }

  private rankRulesForPrompt(message: string, rules: BusinessRuleRecord[]) {
    const tokens = new Set(this.tokenize(message));

    return rules
      .map((rule) => {
        const ruleTokens = new Set(
          this.tokenize([rule.title, rule.summary ?? '', rule.content, rule.module, rule.category].join(' ')),
        );
        let score = 0;
        for (const token of tokens) {
          if (ruleTokens.has(token)) {
            score += token.length >= 5 ? 2 : 1;
          }
        }
        if (rule.severity === 'critical' || rule.severity === 'warning') {
          score += 1;
        }
        return { rule, score };
      })
      .filter((item) => item.score > 0)
      .sort((left, right) => right.score - left.score)
      .map((item) => item.rule);
  }

  private buildExcerpt(content: string) {
    const normalized = content.replace(/\s+/g, ' ').trim();
    if (normalized.length <= 220) return normalized;
    return `${normalized.slice(0, 217).trim()}...`;
  }

  private logDebug(label: string, payload: unknown) {
    if (process.env.NODE_ENV === 'production' && process.env.AI_DEBUG !== '1') {
      return;
    }
    this.logger.debug(`${label}: ${JSON.stringify(payload)}`);
  }
}
