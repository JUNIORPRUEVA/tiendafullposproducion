import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { CompanyManualAudience, CompanyManualEntryKind, DepositOrderStatus, Prisma, Role } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { ChatAiAssistantDto } from './dto/chat-ai-assistant.dto';

type AiRuntimeConfig = {
  apiKey: string;
  model: string;
  companyName: string;
};

type KnowledgeRecord = {
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

type NormalizedAiContext = {
  module: string;
  screenName?: string;
  route?: string;
  entityType?: string;
  entityId?: string;
};

@Injectable()
export class AiAssistantService {
  private readonly logger = new Logger(AiAssistantService.name);

  private static readonly unauthorizedMessage =
    'No puedo ayudar con información privada de otro usuario ni mostrar datos para los que no tienes autorización.';

  private static readonly notEnoughDataMessage =
    'No tengo información suficiente en el sistema para responder eso. Si me das más contexto (módulo, cliente o pantalla), puedo ayudarte mejor.';

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  async chat(user: { id: string; role: Role }, dto: ChatAiAssistantDto) {
    const message = dto.message.trim();
    if (!message) throw new BadRequestException('El mensaje es obligatorio');

    const context = this.normalizeContext(dto.context);

    if (!this.canAccessContext(user.role, context)) {
      return {
        source: 'policy',
        content: AiAssistantService.unauthorizedMessage,
        citations: [],
        denied: true,
      };
    }

    // Hard deny for common secret/credential extraction attempts.
    if (this.isForbiddenSecretRequest(message)) {
      return {
        source: 'policy',
        content: AiAssistantService.unauthorizedMessage,
        citations: [],
        denied: true,
      };
    }

    const effectiveDto = { ...dto, context };

    const knowledge = await this.buildKnowledge(user, effectiveDto);
    this.logDebug('ai.chat.context', context);
    this.logDebug('ai.chat.knowledge', knowledge.map((k) => ({ id: k.id, title: k.title, module: k.module })));

    if (knowledge.length === 0) {
      return {
        source: 'rules-only',
        content: AiAssistantService.notEnoughDataMessage,
        citations: [],
      };
    }

    const runtime = await this.getOpenAiRuntimeConfig();
    if (!runtime.apiKey) {
      return this.buildRuleOnlyFallback(message, knowledge);
    }

    const safeHistory = this.normalizeHistory(dto.history).slice(-8);

    const systemPrompt =
      `Eres el asistente administrativo interno de ${runtime.companyName} dentro de la app FULLTECH. ` +
      'Debes responder de forma humana, clara y profesional. ' +
      'REGLAS DE SEGURIDAD: 1) solo puedes usar el conocimiento interno enviado por el sistema; 2) no inventes; 3) no uses conocimiento externo; 4) no reveles datos privados de otros usuarios; 5) si falta permiso o datos, dilo con respeto. ' +
      'REGLAS DE CALIDAD: si la respuesta es larga, resume al inicio; si el usuario pide pasos, responde paso a paso. ' +
      'Devuelve únicamente JSON válido.';

    const userPrompt =
      `${JSON.stringify({ message, context, history: safeHistory, knowledge })}\n\n` +
      'Devuelve exactamente este JSON: ' +
      '{"content":"string","citations":[{"id":"string","module":"string","category":"string","title":"string"}],"denied":false}. ' +
      'Reglas estrictas: ' +
      '1) si respondes algo útil basado en conocimiento enviado, citations no puede ir vacío; ' +
      '2) no incluyas citas inventadas; ' +
      '3) si el usuario pide información no autorizada, usa denied=true y content debe explicar que no tiene permisos; ' +
      '4) si no hay información suficiente, denied=false y content debe pedir más contexto.';

    const parsed = await this.requestStrictJsonFromOpenAi<{
      content?: unknown;
      citations?: unknown;
      denied?: unknown;
    }>({
      runtime,
      temperature: 0.2,
      systemPrompt,
      userPrompt,
    });

    const content = this.normalizeOptionalString(parsed.content) ?? AiAssistantService.notEnoughDataMessage;
    const citations = this.normalizeCitations(parsed.citations, knowledge);
    const denied = parsed.denied === true;

    // Safety net: If denied then don't allow citations.
    if (denied) {
      return {
        source: 'policy',
        content: this.isUnauthorizedMessage(content) ? content : AiAssistantService.unauthorizedMessage,
        citations: [],
        denied: true,
      };
    }

    // If the model returned something useful but without citations, fall back to deterministic retrieval.
    if (citations.length === 0) {
      return this.buildRuleOnlyFallback(message, knowledge);
    }

    return {
      source: 'openai',
      content,
      citations,
      denied: false,
    };
  }

  private normalizeHistory(raw?: Array<{ role: 'user' | 'assistant'; content: string }>) {
    if (!Array.isArray(raw)) return [];
    return raw
      .map((m) => {
        if (!m || typeof m !== 'object') return null;
        const role = m.role === 'assistant' ? 'assistant' : 'user';
        const content = this.normalizeOptionalString(m.content);
        if (!content) return null;
        return { role, content };
      })
      .filter((m): m is NonNullable<typeof m> => !!m);
  }

  private isUnauthorizedMessage(content: string) {
    const text = content.toLowerCase();
    return text.includes('permiso') || text.includes('autoriz');
  }

  private isForbiddenSecretRequest(message: string) {
    const text = message.toLowerCase();
    return (
      text.includes('api key') ||
      text.includes('apikey') ||
      text.includes('token') ||
      text.includes('password') ||
      text.includes('contraseña') ||
      text.includes('clave') && text.includes('openai')
    );
  }

  private normalizeContext(raw: ChatAiAssistantDto['context']): NormalizedAiContext {
    const route = this.normalizeOptionalString(raw?.route) ?? undefined;
    const routeContext = this.parseRouteContext(route);
    const module = this.normalizeModuleKey(
      this.normalizeOptionalString(raw?.module) ?? routeContext.module ?? 'general',
    ) || 'general';
    const screenName = this.normalizeOptionalString(raw?.screenName) ?? routeContext.screenName ?? undefined;
    const entityType = this.normalizeOptionalString(raw?.entityType) ?? routeContext.entityType ?? undefined;
    const entityId = this.normalizeOptionalString(raw?.entityId) ?? routeContext.entityId ?? undefined;

    return {
      module,
      ...(screenName ? { screenName } : {}),
      ...(route ? { route } : {}),
      ...(entityType ? { entityType } : {}),
      ...(entityId ? { entityId } : {}),
    };
  }

  private parseRouteContext(route?: string) {
    const raw = (route ?? '').trim();
    if (!raw) return {} as Partial<NormalizedAiContext>;

    let uri: URL;
    try {
      uri = new URL(raw, 'https://fulltech.local');
    } catch {
      return {} as Partial<NormalizedAiContext>;
    }

    const path = uri.pathname.trim().toLowerCase();
    const segments = path.split('/').filter(Boolean);
    const result: Partial<NormalizedAiContext> = {};

    if (path.startsWith('/clientes')) {
      result.module = 'clientes';
      result.screenName = segments.length >= 2
        ? (segments[2] === 'editar' ? 'Editar cliente' : 'Detalle de cliente')
        : (segments[1] === 'nuevo' ? 'Nuevo cliente' : 'Clientes');
      if (segments.length >= 2 && segments[1] !== 'nuevo') {
        result.entityType = 'client';
        result.entityId = segments[1];
      }
      return result;
    }

    if (path.startsWith('/catalogo')) return { module: 'catalogo', screenName: 'Catálogo' };
    if (path === '/ventas/nueva') return { module: 'ventas', screenName: 'Registrar venta' };
    if (path.startsWith('/ventas')) return { module: 'ventas', screenName: 'Ventas' };
    if (path === '/operaciones/agenda') return { module: 'operaciones', screenName: 'Agenda de operaciones' };
    if (path === '/operaciones/mapa-clientes') return { module: 'operaciones', screenName: 'Mapa de clientes' };
    if (path === '/operaciones/reglas') return { module: 'operaciones', screenName: 'Reglas operativas' };
    if (path.startsWith('/operaciones')) {
      if (segments.length >= 2 && !['agenda', 'mapa-clientes', 'reglas'].includes(segments[1])) {
        return {
          module: 'operaciones',
          screenName: 'Detalle de servicio',
          entityType: 'service',
          entityId: segments[1],
        };
      }
      return { module: 'operaciones', screenName: 'Operaciones' };
    }
    if (path === '/contabilidad/cierres-diarios') return { module: 'contabilidad', screenName: 'Cierres diarios' };
    if (path === '/contabilidad/factura-fiscal') return { module: 'contabilidad', screenName: 'Facturas fiscales' };
    if (path === '/contabilidad/pagos-pendientes') return { module: 'contabilidad', screenName: 'Pagos pendientes' };
    if (path.startsWith('/contabilidad')) return { module: 'contabilidad', screenName: 'Contabilidad' };
    if (path === '/nomina') return { module: 'nomina', screenName: 'Nómina' };
    if (path === '/mis-pagos') return { module: 'nomina', screenName: 'Mis pagos' };
    if (path.startsWith('/manual-interno')) return { module: 'manual-interno', screenName: 'Manual interno' };
    if (path.startsWith('/configuracion')) return { module: 'configuracion', screenName: 'Configuración' };
    if (path.startsWith('/administracion')) return { module: 'administracion', screenName: 'Administración' };
    if (path === '/cotizaciones/historial') {
      const quoteId = uri.searchParams.get('quoteId')?.trim() ?? '';
      const customerPhone = uri.searchParams.get('customerPhone')?.trim() ?? '';
      return {
        module: 'cotizaciones',
        screenName: 'Historial de cotizaciones',
        ...(quoteId ? { entityType: 'quote', entityId: quoteId } : {}),
        ...(!quoteId && customerPhone ? { entityType: 'client-phone', entityId: customerPhone } : {}),
      };
    }
    if (path.startsWith('/cotizaciones')) return { module: 'cotizaciones', screenName: 'Cotizaciones' };
    if (path.startsWith('/users/')) {
      return {
        module: 'administracion',
        screenName: 'Detalle de usuario',
        entityType: 'user',
        entityId: segments[1],
      };
    }
    if (path === '/users' || path === '/user') return { module: 'administracion', screenName: 'Usuarios' };
    if (path === '/salidas-tecnicas') return { module: 'operaciones', screenName: 'Salidas técnicas' };
    if (path === '/horarios') return { module: 'horarios', screenName: 'Horarios' };
    if (path === '/profile') return { module: 'profile', screenName: 'Perfil' };
    if (path === '/ponche') return { module: 'ponche', screenName: 'Ponche' };

    return { module: 'general' };
  }

  private canAccessContext(role: Role, context: NormalizedAiContext) {
    const path = this.extractPath(context.route);
    if (path) {
      return this.canAccessPath(role, path);
    }
    return this.canAccessModule(role, context.module);
  }

  private extractPath(route?: string) {
    const raw = (route ?? '').trim();
    if (!raw) return '';
    try {
      return new URL(raw, 'https://fulltech.local').pathname.toLowerCase();
    } catch {
      return raw.split('?')[0]?.trim().toLowerCase() ?? '';
    }
  }

  private canAccessPath(role: Role, path: string) {
    if (!path) return true;

    if (path === '/profile') return true;
    if (path === '/mis-pagos') return true;
    if (path === '/horarios') return true;
    if (path === '/ponche') return true;
    if (path === '/salidas-tecnicas') return role === Role.TECNICO;
    if (path.startsWith('/operaciones')) return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.MARKETING, Role.TECNICO]);
    if (path.startsWith('/catalogo')) return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.MARKETING]);
    if (path.startsWith('/ventas')) return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR]);
    if (path.startsWith('/cotizaciones')) return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.MARKETING]);
    if (path.startsWith('/clientes')) return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.MARKETING]);
    if (path.startsWith('/nomina')) return role === Role.ADMIN;
    if (path.startsWith('/manual-interno')) return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.MARKETING, Role.TECNICO]);
    if (path.startsWith('/contabilidad')) return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE]);
    if (path.startsWith('/administracion')) return role === Role.ADMIN;
    if (path.startsWith('/configuracion')) return role === Role.ADMIN;
    if (path === '/users' || path === '/user' || path.startsWith('/users/')) return role === Role.ADMIN;

    return true;
  }

  private canAccessModule(role: Role, module: string) {
    switch (this.normalizeModuleKey(module)) {
      case 'general':
        return true;
      case 'profile':
      case 'ponche':
      case 'horarios':
        return true;
      case 'operaciones':
        return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.MARKETING, Role.TECNICO]);
      case 'catalogo':
        return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.MARKETING]);
      case 'ventas':
        return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR]);
      case 'cotizaciones':
        return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.MARKETING]);
      case 'clientes':
        return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.MARKETING]);
      case 'nomina':
        return role === Role.ADMIN;
      case 'manual-interno':
        return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.MARKETING, Role.TECNICO]);
      case 'contabilidad':
        return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE]);
      case 'administracion':
      case 'configuracion':
        return role === Role.ADMIN;
      default:
        return true;
    }
  }

  private hasRole(role: Role, allowed: Role[]) {
    return allowed.includes(role);
  }

  private canAccessClientData(role: Role) {
    return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR]);
  }

  private canAccessQuoteData(role: Role) {
    return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO]);
  }

  private canAccessSalesData(role: Role) {
    return this.canAccessModule(role, 'ventas');
  }

  private canAccessOperationsData(role: Role) {
    return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO]);
  }

  private canAccessAccountingData(role: Role) {
    return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE]);
  }

  private canAccessContractData(role: Role, route?: string) {
    const path = this.extractPath(route);
    if (path === '/mis-pagos' || path === '/profile') {
      return true;
    }
    return role === Role.ADMIN;
  }

  private async buildKnowledge(user: { id: string; role: Role }, dto: ChatAiAssistantDto): Promise<KnowledgeRecord[]> {
    const ownerId = await this.resolveCompanyOwnerId(user.id);

    const manualEntries = await this.prisma.companyManualEntry.findMany({
      where: {
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
      },
      orderBy: [{ sortOrder: 'asc' }, { updatedAt: 'desc' }, { title: 'asc' }],
      take: 180,
    });

    const staticHelp = this.buildStaticModuleHelp();
    const authorizedData = await this.buildAuthorizedDataKnowledge(user, dto);

    const all = [
      ...manualEntries.map((entry) => this.toManualKnowledge(entry)),
      ...staticHelp,
      ...authorizedData,
    ];

    // Rank and reduce to keep the prompt compact.
    const ranked = this.rankKnowledgeForPrompt(dto.message, dto.context, all);
    return ranked.slice(0, 14);
  }

  private buildStaticModuleHelp(): KnowledgeRecord[] {
    return [
      this.createAppKnowledgeRecord(
        'app-help:general',
        'general',
        'guia-app',
        'Cómo pedir ayuda al asistente',
        'Puedes preguntarme sobre cómo usar módulos, qué significa una opción, qué dice el Manual Interno y dónde encontrar información. Si estás en una pantalla específica, dime el módulo (clientes, catálogo, operaciones, ventas, cotizaciones, nómina, manual interno, configuración) y qué estás intentando lograr.',
      ),
      this.createAppKnowledgeRecord(
        'app-help:clientes',
        'clientes',
        'guia-app',
        'Uso del módulo de clientes',
        'En Clientes puedes buscar, crear y consultar clientes. En detalle de cliente puedes ver datos básicos, historial y procesos relacionados según tu rol. Si necesitas algo específico, dime el cliente y qué deseas revisar.',
      ),
      this.createAppKnowledgeRecord(
        'app-help:cotizaciones',
        'cotizaciones',
        'guia-app',
        'Uso del módulo de cotizaciones',
        'En Cotizaciones puedes preparar propuestas, revisar historial y validar reglas comerciales del Manual Interno. Si ya tienes una cotización abierta o un cliente seleccionado, el asistente prioriza ese contexto.',
      ),
      this.createAppKnowledgeRecord(
        'app-help:catalogo',
        'catalogo',
        'guia-app',
        'Uso del módulo de catálogo',
        'En Catálogo puedes ver productos por categoría y revisar información del catálogo. La visibilidad de precios depende de tu rol.',
      ),
      this.createAppKnowledgeRecord(
        'app-help:ventas',
        'ventas',
        'guia-app',
        'Uso del módulo de ventas',
        'En Ventas puedes registrar operaciones comerciales y revisar tus ventas autorizadas. Si necesitas soporte operativo, indica si estás registrando una venta nueva o revisando ventas anteriores.',
      ),
      this.createAppKnowledgeRecord(
        'app-help:operaciones',
        'operaciones',
        'guia-app',
        'Uso del módulo de operaciones',
        'En Operaciones puedes consultar servicios, fases, asignaciones, archivos y garantías según permisos. Si me dices el número de servicio o el cliente, puedo orientarte sobre el flujo permitido.',
      ),
      this.createAppKnowledgeRecord(
        'app-help:contabilidad',
        'contabilidad',
        'guia-app',
        'Uso del módulo de contabilidad',
        'En Contabilidad puedes registrar cierres, órdenes de depósito, facturas fiscales y pagos pendientes si tu rol lo permite. El asistente puede explicar la pantalla actual y resumir datos autorizados del módulo.',
      ),
      this.createAppKnowledgeRecord(
        'app-help:nomina',
        'nomina',
        'guia-app',
        'Uso del módulo de nómina',
        'Nómina contiene información sensible. Solo usuarios autorizados pueden ver datos de empleados. Puedes consultar tu información personal si aplica.',
      ),
      this.createAppKnowledgeRecord(
        'app-help:manual',
        'manual-interno',
        'guia-app',
        'Manual Interno',
        'El Manual Interno es la base principal de reglas, protocolos, políticas y guías por rol. El asistente responde priorizando estas reglas oficiales.',
      ),
      this.createAppKnowledgeRecord(
        'app-help:seguridad',
        'seguridad',
        'politica-app',
        'Política de privacidad del asistente',
        'El asistente nunca debe revelar credenciales, tokens, contraseñas ni información privada de otros usuarios. Si algo no está permitido por tu rol, el asistente lo rechazará.',
      ),
    ];
  }

  private async buildAuthorizedDataKnowledge(
    user: { id: string; role: Role },
    dto: ChatAiAssistantDto,
  ): Promise<KnowledgeRecord[]> {
    const contextText = [
      dto.message,
      dto.context.module ?? '',
      dto.context.screenName ?? '',
      dto.context.route ?? '',
      dto.context.entityType ?? '',
    ].join(' ');
    const tokens = new Set(this.tokenize(contextText));
    const includeModuleContext = tokens.size === 0;

    const wantsClients = includeModuleContext || this.hasAnyToken(tokens, ['cliente', 'clientes']);
    const wantsCatalog = includeModuleContext || this.hasAnyToken(tokens, ['producto', 'productos', 'catalogo', 'catálogo', 'precio', 'precios']);
    const wantsContracts = includeModuleContext || this.hasAnyToken(tokens, ['contrato', 'nomina', 'nómina', 'salario', 'clausula', 'cláusula']);
    const wantsQuotes = includeModuleContext || this.hasAnyToken(tokens, ['cotizacion', 'cotizaciones', 'ticket', 'propuesta']);
    const wantsSales = includeModuleContext || this.hasAnyToken(tokens, ['venta', 'ventas', 'comision', 'comisión']);
    const wantsOperations = includeModuleContext || this.hasAnyToken(tokens, ['servicio', 'servicios', 'operacion', 'operaciones', 'garantia', 'garantía']);
    const wantsAccounting = includeModuleContext || this.hasAnyToken(tokens, ['contabilidad', 'cierre', 'cierres', 'deposito', 'depósito', 'factura', 'pago']);
    const wantsSelf = includeModuleContext || this.isSelfInfoRequest(dto.message, dto.context);

    const knowledge: KnowledgeRecord[] = [];

    if (wantsSelf) {
      const selfKnowledge = await this.buildSelfKnowledge(user, dto);
      knowledge.push(...selfKnowledge);
    }

    // CLIENTS: scope strictly to what the user can access.
    if ((wantsClients || dto.context.module === 'clientes') && this.canAccessClientData(user.role)) {
      const clientKnowledge = await this.buildClientKnowledge(user, dto);
      knowledge.push(...clientKnowledge);
    }

    if ((wantsCatalog || dto.context.module === 'catalogo') && this.canAccessModule(user.role, 'catalogo')) {
      const catalogKnowledge = await this.buildCatalogKnowledge(user, dto);
      knowledge.push(...catalogKnowledge);
    }

    if ((wantsContracts || dto.context.module === 'nomina') && this.canAccessContractData(user.role, dto.context.route)) {
      const contractKnowledge = await this.buildContractKnowledge(user, dto);
      knowledge.push(...contractKnowledge);
    }

    if ((wantsQuotes || dto.context.module === 'cotizaciones') && this.canAccessQuoteData(user.role)) {
      const quoteKnowledge = await this.buildQuoteKnowledge(user, dto);
      knowledge.push(...quoteKnowledge);
    }

    if ((wantsSales || dto.context.module === 'ventas') && this.canAccessSalesData(user.role)) {
      const salesKnowledge = await this.buildSalesKnowledge(user, dto);
      knowledge.push(...salesKnowledge);
    }

    if ((wantsOperations || dto.context.module === 'operaciones') && this.canAccessOperationsData(user.role)) {
      const operationsKnowledge = await this.buildOperationsKnowledge(user, dto);
      knowledge.push(...operationsKnowledge);
    }

    if ((wantsAccounting || dto.context.module === 'contabilidad') && this.canAccessAccountingData(user.role)) {
      const accountingKnowledge = await this.buildAccountingKnowledge(user, dto);
      knowledge.push(...accountingKnowledge);
    }

    return knowledge;
  }

  private isSelfInfoRequest(message: string, context: NormalizedAiContext) {
    const raw = message.trim().toLowerCase();
    if (context.module === 'profile' || context.module === 'nomina') {
      return true;
    }

    return (
      /(^|\s)(mi|mis|yo|mio|mía|mias|mios)(\s|$)/i.test(raw) ||
      raw.includes('mi nombre') ||
      raw.includes('mi correo') ||
      raw.includes('mi email') ||
      raw.includes('mi telefono') ||
      raw.includes('mi teléfono') ||
      raw.includes('mi rol') ||
      raw.includes('mi usuario') ||
      raw.includes('mi perfil') ||
      raw.includes('de mi')
    );
  }

  private async buildSelfKnowledge(
    user: { id: string; role: Role },
    dto: ChatAiAssistantDto,
  ): Promise<KnowledgeRecord[]> {
    const record = await this.prisma.user.findUnique({
      where: { id: user.id },
      select: {
        id: true,
        nombreCompleto: true,
        email: true,
        telefono: true,
        role: true,
        fechaIngreso: true,
        workContractJobTitle: true,
      },
    });

    if (!record) return [];

    const result: KnowledgeRecord[] = [
      this.createAppKnowledgeRecord(
        `app-data:self:${record.id}`,
        'profile',
        'dato-autorizado',
        'Perfil del usuario actual',
        `Tu nombre en la app es ${record.nombreCompleto}. Correo: ${record.email}. Teléfono: ${record.telefono}. Rol: ${record.role}. ${record.workContractJobTitle ? `Puesto: ${record.workContractJobTitle}. ` : ''}${record.fechaIngreso ? `Fecha de ingreso: ${record.fechaIngreso.toISOString().slice(0, 10)}.` : ''}`,
      ),
    ];

    if (dto.context.module === 'profile') {
      result.push(
        this.createAppKnowledgeRecord(
          'app-data:self:profile-help',
          'profile',
          'guia-app',
          'Ayuda del perfil',
          'En Perfil puedes revisar tu información personal dentro de la app. El asistente puede responder usando únicamente tus propios datos autorizados.',
        ),
      );
    }

    return result;
  }

  private async buildClientKnowledge(user: { id: string; role: Role }, dto: ChatAiAssistantDto): Promise<KnowledgeRecord[]> {
    const isAdmin = user.role === Role.ADMIN;

    const accessibleWhere: Prisma.ClientWhereInput = isAdmin
      ? { isDeleted: false }
      : {
          isDeleted: false,
          OR: [
            { ownerId: user.id },
            { services: { some: { OR: [{ technicianId: user.id }, { createdByUserId: user.id }] } } },
          ],
        };

    const count = await this.prisma.client.count({ where: accessibleWhere });

    const base = [
      this.createAppKnowledgeRecord(
        'app-data:clients-scope',
        'clientes',
        'dato-autorizado',
        'Alcance autorizado de clientes',
        isAdmin
          ? 'Como ADMIN puedes consultar clientes del sistema según las pantallas permitidas.'
          : 'Solo puedes consultar clientes bajo tu gestión o relacionados con tus servicios/operaciones asignadas.',
      ),
      this.createAppKnowledgeRecord(
        'app-data:clients-count',
        'clientes',
        'dato-autorizado',
        'Resumen autorizado de clientes',
        isAdmin ? `Actualmente hay ${count} clientes activos.` : `Actualmente tienes acceso a ${count} clientes activos.`,
      ),
    ];

    const entityId = (dto.context.entityType ?? '').toLowerCase() === 'client' ? (dto.context.entityId ?? '').trim() : '';
    if (!entityId) return base;

    const client = await this.prisma.client.findFirst({
      where: { ...accessibleWhere, id: entityId },
      select: {
        id: true,
        nombre: true,
        lastActivityAt: true,
        notas: true,
      },
    });

    if (!client) {
      base.push(
        this.createAppKnowledgeRecord(
          'app-data:client-denied',
          'clientes',
          'dato-autorizado',
          'Cliente no accesible',
          'No tengo autorización para acceder a ese cliente (o no existe).',
        ),
      );
      return base;
    }

    const serviceCount = await this.prisma.service.count({ where: { customerId: client.id } });
    const saleCount = await this.prisma.sale.count({ where: { customerId: client.id, isDeleted: false } });

    base.push(
      this.createAppKnowledgeRecord(
        `app-data:client:${client.id}`,
        'clientes',
        'dato-autorizado',
        `Cliente seleccionado: ${client.nombre}`,
        `Cliente: ${client.nombre}. Servicios registrados: ${serviceCount}. Ventas registradas: ${saleCount}. Última actividad: ${client.lastActivityAt ? client.lastActivityAt.toISOString() : 'N/D'}.`,
      ),
    );

    // Avoid leaking notes unless admin (notes may contain sensitive info).
    if (isAdmin && (client.notas ?? '').trim().length > 0) {
      base.push(
        this.createAppKnowledgeRecord(
          `app-data:client:${client.id}:notes`,
          'clientes',
          'dato-autorizado',
          'Notas internas del cliente (ADMIN)',
          this.buildExcerpt(client.notas ?? ''),
        ),
      );
    }

    return base;
  }

  private async buildCatalogKnowledge(user: { id: string; role: Role }, dto: ChatAiAssistantDto): Promise<KnowledgeRecord[]> {
    const tokens = this.tokenize(dto.message);
    const searchTokens = tokens.filter((token) => !this.isCatalogNoiseToken(token)).slice(0, 5);

    const total = await this.prisma.product.count();
    const topCategories = await this.prisma.product.groupBy({
      by: ['categoria'],
      _count: { categoria: true },
      orderBy: { _count: { categoria: 'desc' } },
      take: 5,
    });

    const result: KnowledgeRecord[] = [
      this.createAppKnowledgeRecord(
        'app-data:catalog-count',
        'catalogo',
        'dato-autorizado',
        'Resumen autorizado de catálogo',
        `Actualmente hay ${total} productos en el catálogo.`,
      ),
      this.createAppKnowledgeRecord(
        'app-data:catalog-categories',
        'catalogo',
        'dato-autorizado',
        'Categorías principales del catálogo',
        topCategories.length > 0
          ? topCategories
              .map((item) => `- ${item.categoria || 'Sin categoría'}: ${item._count.categoria}`)
              .join('\n')
          : 'No hay categorías disponibles en el catálogo.',
      ),
    ];

    if (searchTokens.length === 0) return result;

    const products = await this.prisma.product.findMany({
      where: {
        OR: [
          ...searchTokens.map((token) => ({ nombre: { contains: token, mode: 'insensitive' as const } })),
          ...searchTokens.map((token) => ({ categoria: { contains: token, mode: 'insensitive' as const } })),
        ],
      },
      select: { id: true, nombre: true, categoria: true, precio: true },
      take: 12,
      orderBy: { nombre: 'asc' },
    });

    if (products.length === 0) {
      result.push(
        this.createAppKnowledgeRecord(
          'app-data:catalog-search-none',
          'catalogo',
          'dato-autorizado',
          'Producto no encontrado en catálogo',
          `No encontré productos en el catálogo que coincidan con: ${searchTokens.join(', ')}. Si buscas disponibilidad física o inventario en tiempo real, eso debe confirmarse en el módulo correspondiente.`,
        ),
      );
      return result;
    }

    const rankedProducts = products
      .map((product) => ({
        product,
        score: searchTokens.reduce((sum, token) => {
          const haystack = `${product.nombre} ${product.categoria}`.toLowerCase();
          return haystack.includes(token) ? sum + 1 : sum;
        }, 0),
      }))
      .sort((a, b) => b.score - a.score || a.product.nombre.localeCompare(b.product.nombre))
      .slice(0, 6)
      .map((item) => item.product);

    const lines = rankedProducts.map((p) => {
      const price = user.role === Role.TECNICO ? '' : ` | Precio: ${p.precio.toFixed(2)}`;
      return `- ${p.nombre} (${p.categoria})${price}`;
    });

    result.push(
      this.createAppKnowledgeRecord(
        'app-data:catalog-search',
        'catalogo',
        'dato-autorizado',
        `Productos relacionados con "${searchTokens.join(' ')}"`,
        `${lines.join('\n')}\n\nNota: esto confirma coincidencias en el catálogo, no inventario físico en tiempo real.`,
      ),
    );

    return result;
  }

  private isCatalogNoiseToken(token: string) {
    return [
      'hay',
      'tengo',
      'tienen',
      'producto',
      'productos',
      'disponible',
      'disponibles',
      'precio',
      'precios',
      'catalogo',
      'catalogos',
      'catálogo',
      'app',
      'quiero',
      'buscar',
      'busca',
      'muestrame',
      'muéstrame',
      'necesito',
      'dime',
    ].includes(token);
  }

  private async buildQuoteKnowledge(user: { id: string; role: Role }, dto: ChatAiAssistantDto): Promise<KnowledgeRecord[]> {
    const where: Prisma.CotizacionWhereInput = user.role === Role.ADMIN
      ? {}
      : { createdByUserId: user.id };

    const totalQuotes = await this.prisma.cotizacion.count({ where });
    const result: KnowledgeRecord[] = [
      this.createAppKnowledgeRecord(
        'app-data:quotes-scope',
        'cotizaciones',
        'dato-autorizado',
        'Alcance autorizado de cotizaciones',
        user.role === Role.ADMIN
          ? 'Puedes consultar cotizaciones del sistema según las pantallas administrativas permitidas.'
          : 'Solo puedes consultar cotizaciones creadas bajo tu usuario dentro del alcance permitido por el sistema.',
      ),
      this.createAppKnowledgeRecord(
        'app-data:quotes-count',
        'cotizaciones',
        'dato-autorizado',
        'Resumen autorizado de cotizaciones',
        user.role === Role.ADMIN
          ? `Actualmente hay ${totalQuotes} cotizaciones registradas.`
          : `Actualmente tienes acceso a ${totalQuotes} cotizaciones registradas bajo tu usuario.`,
      ),
    ];

    const entityType = (dto.context.entityType ?? '').trim().toLowerCase();
    const entityId = (dto.context.entityId ?? '').trim();

    if (entityType === 'quote' && entityId) {
      const quote = await this.prisma.cotizacion.findFirst({
        where: { ...where, id: entityId },
        select: {
          id: true,
          customerName: true,
          total: true,
          subtotal: true,
          includeItbis: true,
          note: true,
          createdAt: true,
          items: {
            select: { id: true },
          },
        },
      });

      if (!quote) {
        result.push(
          this.createAppKnowledgeRecord(
            'app-data:quote-denied',
            'cotizaciones',
            'dato-autorizado',
            'Cotización no accesible',
            'No tengo autorización para acceder a esa cotización o no existe dentro de tu alcance.',
          ),
        );
        return result;
      }

      result.push(
        this.createAppKnowledgeRecord(
          `app-data:quote:${quote.id}`,
          'cotizaciones',
          'dato-autorizado',
          `Cotización seleccionada para ${quote.customerName}`,
          `Cliente: ${quote.customerName}. Total: ${quote.total.toFixed(2)}. Subtotal: ${quote.subtotal.toFixed(2)}. ITBIS incluido: ${quote.includeItbis ? 'sí' : 'no'}. Líneas: ${quote.items.length}. Creada: ${quote.createdAt.toISOString()}. ${quote.note ? `Nota: ${this.buildExcerpt(quote.note)}.` : ''}`,
        ),
      );
    }

    return result;
  }

  private async buildSalesKnowledge(user: { id: string; role: Role }, dto: ChatAiAssistantDto): Promise<KnowledgeRecord[]> {
    const where: Prisma.SaleWhereInput = user.role === Role.ADMIN
      ? { isDeleted: false }
      : { userId: user.id, isDeleted: false };

    const [count, latest] = await this.prisma.$transaction([
      this.prisma.sale.count({ where }),
      this.prisma.sale.findFirst({
        where,
        orderBy: { saleDate: 'desc' },
        select: {
          id: true,
          saleDate: true,
          totalSold: true,
          commissionAmount: true,
          customer: { select: { nombre: true } },
        },
      }),
    ]);

    const result: KnowledgeRecord[] = [
      this.createAppKnowledgeRecord(
        'app-data:sales-count',
        'ventas',
        'dato-autorizado',
        'Resumen autorizado de ventas',
        user.role === Role.ADMIN
          ? `Actualmente hay ${count} ventas activas registradas en el sistema.`
          : `Actualmente tienes ${count} ventas activas registradas bajo tu usuario.`,
      ),
    ];

    if (latest) {
      result.push(
        this.createAppKnowledgeRecord(
          `app-data:sale:latest:${latest.id}`,
          'ventas',
          'dato-autorizado',
          'Última venta autorizada',
          `Última venta registrada: ${latest.saleDate.toISOString()}. Cliente: ${latest.customer?.nombre ?? 'N/D'}. Total vendido: ${latest.totalSold.toFixed(2)}. Comisión: ${latest.commissionAmount.toFixed(2)}.`,
        ),
      );
    }

    const clientEntityId = (dto.context.entityType ?? '').toLowerCase() === 'client'
      ? (dto.context.entityId ?? '').trim()
      : '';
    if (clientEntityId) {
      const clientSalesCount = await this.prisma.sale.count({
        where: { ...where, customerId: clientEntityId },
      });
      result.push(
        this.createAppKnowledgeRecord(
          `app-data:sales-client:${clientEntityId}`,
          'ventas',
          'dato-autorizado',
          'Ventas del cliente seleccionado',
          `Ventas autorizadas relacionadas con el cliente actual: ${clientSalesCount}.`,
        ),
      );
    }

    return result;
  }

  private async buildOperationsKnowledge(user: { id: string; role: Role }, dto: ChatAiAssistantDto): Promise<KnowledgeRecord[]> {
    if (user.role === Role.MARKETING) {
      return [
        this.createAppKnowledgeRecord(
          'app-data:operations-scope-marketing',
          'operaciones',
          'dato-autorizado',
          'Alcance operativo limitado',
          'Tu rol puede recibir guía general del módulo, pero no datos operativos detallados desde el asistente.',
        ),
      ];
    }

    const where: Prisma.ServiceWhereInput =
      user.role === Role.ADMIN || user.role === Role.ASISTENTE
        ? { isDeleted: false }
        : user.role === Role.VENDEDOR
          ? { isDeleted: false, createdByUserId: user.id }
          : user.role === Role.TECNICO
            ? { isDeleted: false, assignments: { some: { userId: user.id } } }
            : { id: '__none__' };

    const [count, latest] = await this.prisma.$transaction([
      this.prisma.service.count({ where }),
      this.prisma.service.findFirst({
        where,
        orderBy: { updatedAt: 'desc' },
        select: {
          id: true,
          title: true,
          status: true,
          currentPhase: true,
          updatedAt: true,
          customer: { select: { nombre: true } },
        },
      }),
    ]);

    const result: KnowledgeRecord[] = [
      this.createAppKnowledgeRecord(
        'app-data:operations-count',
        'operaciones',
        'dato-autorizado',
        'Resumen autorizado de servicios',
        user.role === Role.ADMIN || user.role === Role.ASISTENTE
          ? `Actualmente hay ${count} servicios activos visibles para tu rol.`
          : `Actualmente tienes acceso a ${count} servicios operativos relacionados con tu usuario.`,
      ),
    ];

    if (latest) {
      result.push(
        this.createAppKnowledgeRecord(
          `app-data:service:latest:${latest.id}`,
          'operaciones',
          'dato-autorizado',
          'Servicio operativo reciente',
          `Servicio: ${latest.title}. Cliente: ${latest.customer.nombre}. Estado: ${latest.status}. Fase actual: ${latest.currentPhase}. Última actualización: ${latest.updatedAt.toISOString()}.`,
        ),
      );
    }

    const entityType = (dto.context.entityType ?? '').toLowerCase();
    const entityId = (dto.context.entityId ?? '').trim();
    if (entityType === 'service' && entityId) {
      const service = await this.prisma.service.findFirst({
        where: { ...where, id: entityId },
        select: {
          id: true,
          title: true,
          status: true,
          currentPhase: true,
          paymentStatus: true,
          scheduledStart: true,
          customer: { select: { nombre: true } },
        },
      });

      if (!service) {
        result.push(
          this.createAppKnowledgeRecord(
            'app-data:service-denied',
            'operaciones',
            'dato-autorizado',
            'Servicio no accesible',
            'No tengo autorización para acceder a ese servicio o no existe dentro de tu alcance.',
          ),
        );
        return result;
      }

      result.push(
        this.createAppKnowledgeRecord(
          `app-data:service:${service.id}`,
          'operaciones',
          'dato-autorizado',
          `Servicio seleccionado: ${service.title}`,
          `Cliente: ${service.customer.nombre}. Estado: ${service.status}. Fase: ${service.currentPhase}. Estado de pago: ${service.paymentStatus}. Inicio programado: ${service.scheduledStart ? service.scheduledStart.toISOString() : 'N/D'}.`,
        ),
      );
    }

    return result;
  }

  private async buildAccountingKnowledge(user: { id: string; role: Role }, dto: ChatAiAssistantDto): Promise<KnowledgeRecord[]> {
    const todayStart = new Date();
    todayStart.setHours(0, 0, 0, 0);
    const todayEnd = new Date();
    todayEnd.setHours(23, 59, 59, 999);

    const [closeCount, pendingDepositOrders, latestClose] = await this.prisma.$transaction([
      this.prisma.close.count({ where: { date: { gte: todayStart, lte: todayEnd } } }),
      this.prisma.depositOrder.count({ where: { status: DepositOrderStatus.PENDING } }),
      this.prisma.close.findFirst({
        orderBy: [{ date: 'desc' }, { createdAt: 'desc' }],
        select: {
          id: true,
          type: true,
          date: true,
          cash: true,
          transfer: true,
          card: true,
        },
      }),
    ]);

    const result: KnowledgeRecord[] = [
      this.createAppKnowledgeRecord(
        'app-data:accounting-summary',
        'contabilidad',
        'dato-autorizado',
        'Resumen autorizado de contabilidad',
        `Cierres registrados hoy: ${closeCount}. Órdenes de depósito pendientes: ${pendingDepositOrders}.`,
      ),
    ];

    if (latestClose) {
      result.push(
        this.createAppKnowledgeRecord(
          `app-data:close:latest:${latestClose.id}`,
          'contabilidad',
          'dato-autorizado',
          'Último cierre registrado',
          `Tipo: ${latestClose.type}. Fecha: ${latestClose.date.toISOString()}. Efectivo: ${latestClose.cash.toFixed(2)}. Transferencia: ${latestClose.transfer.toFixed(2)}. Tarjeta: ${latestClose.card.toFixed(2)}.`,
        ),
      );
    }

    return result;
  }

  private async buildContractKnowledge(user: { id: string; role: Role }, dto: ChatAiAssistantDto): Promise<KnowledgeRecord[]> {
    const isAdmin = user.role === Role.ADMIN;

    const base: KnowledgeRecord[] = [
      this.createAppKnowledgeRecord(
        'app-data:contracts-policy',
        'nomina',
        'politica-app',
        'Acceso a contratos y nómina',
        'Los contratos y la nómina contienen información sensible. Solo se permite acceso según el rol y el alcance del usuario. Por defecto, un usuario solo puede consultar su propio contrato.',
      ),
    ];

    // Non-admin: allow only own contract snapshot.
    const targetUserId = isAdmin ? user.id : user.id;

    const record = await this.prisma.user.findUnique({
      where: { id: targetUserId },
      select: {
        id: true,
        nombreCompleto: true,
        workContractSignedAt: true,
        workContractJobTitle: true,
        workContractStartDate: true,
        workContractWorkSchedule: true,
        workContractWorkLocation: true,
        workContractSalary: true,
        workContractPaymentFrequency: true,
      },
    });

    if (!record) return base;

    const salaryPart = record.workContractSalary ? `Salario: ${record.workContractSalary}. ` : '';

    base.push(
      this.createAppKnowledgeRecord(
        `app-data:contract:${record.id}`,
        'nomina',
        'dato-autorizado',
        'Contrato laboral (alcance personal)',
        `Empleado: ${record.nombreCompleto}. ` +
          `Puesto: ${record.workContractJobTitle ?? 'N/D'}. ` +
          `Inicio: ${record.workContractStartDate ? record.workContractStartDate.toISOString().slice(0, 10) : 'N/D'}. ` +
          `Horario: ${record.workContractWorkSchedule ?? 'N/D'}. ` +
          `Lugar: ${record.workContractWorkLocation ?? 'N/D'}. ` +
          `${salaryPart}` +
          `Frecuencia: ${record.workContractPaymentFrequency ?? 'N/D'}. ` +
          `Firmado: ${record.workContractSignedAt ? record.workContractSignedAt.toISOString() : 'N/D'}.`,
      ),
    );

    if (isAdmin) {
      base.push(
        this.createAppKnowledgeRecord(
          'app-data:contracts-admin-note',
          'nomina',
          'politica-app',
          'Nota para ADMIN',
          'Para consultar contratos de otros empleados, usa los módulos administrativos correspondientes. El asistente no debe exponer contratos de terceros a roles no autorizados.',
        ),
      );
    }

    return base;
  }

  private rankKnowledgeForPrompt(prompt: string, context: NormalizedAiContext, all: KnowledgeRecord[]) {
    const desired = new Set([
      context.module,
      this.normalizeModuleKey(context.module),
      'manual-interno',
      'seguridad',
    ].filter(Boolean));
    const tokens = new Set(
      this.tokenize([
        prompt,
        context.module,
        context.screenName ?? '',
        context.route ?? '',
        context.entityType ?? '',
      ].join(' ')),
    );

    return all
      .map((entry) => {
        const module = this.normalizeModuleKey(entry.module);
        const text = `${entry.title} ${entry.summary ?? ''} ${entry.content} ${entry.category} ${module}`.toLowerCase();
        const entryTokens = new Set(this.tokenize(text));
        let score = 0;

        if (!module) score += 5;
        if (desired.has(module)) score += 8;

        for (const token of tokens) {
          if (entryTokens.has(token)) score += token.length >= 5 ? 2 : 1;
        }

        if (entry.severity === 'critical') score += 2;
        if (entry.severity === 'warning') score += 1;

        return { entry, score };
      })
      .filter((x) => x.score > 0)
      .sort((a, b) => b.score - a.score)
      .map((x) => x.entry);
  }

  private normalizeModuleKey(raw: string) {
    return (raw ?? '').trim().toLowerCase().replaceAll('_', '-');
  }

  private toManualKnowledge(entry: any): KnowledgeRecord {
    const moduleKey = (entry.moduleKey ?? '').toString().trim().toLowerCase();
    const category = this.mapRuleCategory(entry.kind as CompanyManualEntryKind);
    const title = (entry.title ?? '').toString();
    const content = (entry.content ?? '').toString();
    const summary = entry.summary ? String(entry.summary) : null;

    return {
      id: String(entry.id),
      module: moduleKey.length ? moduleKey : 'general',
      category,
      title,
      content,
      summary,
      keywords: this.tokenize(`${title} ${summary ?? ''} ${content} ${moduleKey} ${category}`).slice(0, 18),
      severity: this.inferSeverity(entry.kind as CompanyManualEntryKind, title, content),
      active: entry.published === true,
      createdAt: entry.createdAt ? entry.createdAt.toISOString() : null,
      updatedAt: entry.updatedAt ? entry.updatedAt.toISOString() : null,
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

  private createAppKnowledgeRecord(id: string, module: string, category: string, title: string, content: string): KnowledgeRecord {
    return {
      id,
      module,
      category,
      title,
      content,
      summary: null,
      keywords: this.tokenize(`${title} ${content} ${module} ${category}`).slice(0, 18),
      severity: 'info',
      active: true,
      createdAt: null,
      updatedAt: null,
    };
  }

  private buildRuleOnlyFallback(message: string, knowledge: KnowledgeRecord[]) {
    const normalizedMessage = message.trim().toLowerCase();
    const hasMeaningfulQuestion = this.tokenize(normalizedMessage).length > 0;
    const matched = hasMeaningfulQuestion ? this.rankRulesForPrompt(message, knowledge).slice(0, 2) : [];
    const top = matched[0] ?? knowledge[0];

    if (!top) {
      return { source: 'rules-only', content: AiAssistantService.notEnoughDataMessage, citations: [] };
    }

    const selected = matched.length ? matched : [top];
    const citations = selected.map((k) => this.toCitation(k));

    const parts = selected
      .map((k, index) => {
        const excerpt = this.buildExcerpt((k.summary ?? '').trim().length ? (k.summary as string) : k.content);
        const prefix = index === 0 ? `Según "${k.title}"` : `También aplica "${k.title}"`;
        return excerpt.length ? `${prefix}: ${excerpt}` : prefix;
      })
      .filter((x) => x.trim().length > 0);

    return {
      source: 'rules-only',
      content: parts.length ? parts.join(' ') : AiAssistantService.notEnoughDataMessage,
      citations,
      denied: false,
    };
  }

  private rankRulesForPrompt(message: string, knowledge: KnowledgeRecord[]) {
    const tokens = new Set(this.tokenize(message));

    return knowledge
      .map((k) => {
        const kTokens = new Set(this.tokenize(`${k.title} ${k.summary ?? ''} ${k.content} ${k.module} ${k.category}`));
        let score = 0;
        for (const token of tokens) {
          if (kTokens.has(token)) score += token.length >= 5 ? 2 : 1;
        }
        if (k.severity === 'critical') score += 2;
        if (k.severity === 'warning') score += 1;
        return { k, score };
      })
      .filter((x) => x.score > 0)
      .sort((a, b) => b.score - a.score)
      .map((x) => x.k);
  }

  private toCitation(k: KnowledgeRecord) {
    return { id: k.id, module: k.module, category: k.category, title: k.title };
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

  private hasAnyToken(tokens: Set<string>, candidates: string[]) {
    for (const c of candidates) {
      const normalized = this.tokenize(c).join(' ');
      for (const token of this.tokenize(normalized)) {
        if (tokens.has(token)) return true;
      }
      if (tokens.has(this.tokenize(c).join(''))) return true;
    }
    return false;
  }

  private buildExcerpt(content: string) {
    const normalized = content.replace(/\s+/g, ' ').trim();
    if (normalized.length <= 240) return normalized;
    return `${normalized.slice(0, 237).trim()}...`;
  }

  private normalizeOptionalString(value: unknown) {
    if (typeof value !== 'string') return null;
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
  }

  private normalizeCitations(raw: unknown, knowledge: KnowledgeRecord[]) {
    if (!Array.isArray(raw)) return [];
    return raw
      .map((item) => {
        if (typeof item !== 'object' || item === null || Array.isArray(item)) return null;
        const row = item as Record<string, unknown>;
        const id = this.normalizeOptionalString(row.id);
        const entry = knowledge.find((k) => k.id === id);
        if (!entry) return null;
        return this.toCitation(entry);
      })
      .filter((x): x is NonNullable<typeof x> => !!x);
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

    let appConfig: { openAiApiKey: string | null; openAiModel: string | null; companyName: string | null } | null = null;

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
      model: envModel.length > 0 ? envModel : ((appConfig?.openAiModel ?? '').trim() || 'gpt-4o-mini'),
      companyName: (appConfig?.companyName ?? 'FULLTECH').trim() || 'FULLTECH',
    };
  }

  private getOpenAiModelCandidates(preferredModel: string) {
    const autoCandidatesEnv = (process.env.OPENAI_MODEL_CANDIDATES ?? '').trim();
    const autoCandidates = autoCandidatesEnv.length > 0
      ? autoCandidatesEnv.split(',').map((x) => x.trim()).filter((x) => x.length > 0)
      : ['gpt-5', 'gpt-4.1', 'gpt-4o', 'gpt-4o-mini'];

    return [preferredModel, ...autoCandidates].filter((value, index, list) => value.length > 0 && list.indexOf(value) === index);
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
    const candidates = this.getOpenAiModelCandidates(runtime.model);

    for (const candidate of candidates) {
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

        const payload = (await response.json()) as { choices?: Array<{ message?: { content?: string } }> };
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

    throw new BadRequestException('No se pudo generar una respuesta válida desde OpenAI para el asistente.');
  }

  private logDebug(label: string, payload: unknown) {
    if (process.env.NODE_ENV === 'production' && process.env.AI_DEBUG !== '1') {
      return;
    }
    this.logger.debug(`${label}: ${JSON.stringify(payload)}`);
  }
}
