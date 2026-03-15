import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { CompanyManualAudience, CompanyManualEntryKind, DepositOrderStatus, Prisma, Role } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CatalogProductsService } from '../products/catalog-products.service';
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

type AiAssistantCitation = {
  id: string;
  module: string;
  category: string;
  title: string;
};

type AiAssistantChatResponse = {
  source: 'policy' | 'rules-only' | 'openai';
  content: string;
  citations: AiAssistantCitation[];
  denied?: boolean;
};

type PersistedAssistantMemoryRow = {
  id: string;
  module: string;
  scope: string;
  topicKey: string;
  title: string;
  summary: string;
  keywords: Prisma.JsonValue | null;
  sourceCount: number;
  lastSourceAt: Date | string | null;
  createdAt: Date | string | null;
  updatedAt: Date | string | null;
};

type PersistedConversationTurnRow = {
  userMessage: string;
  assistantResponse: string;
  module: string;
  createdAt: Date | string | null;
};

type AssistantMemoryNote = {
  scope: 'user';
  module: string;
  topicKey: string;
  title: string;
  summary: string;
  keywords: string[];
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
    private readonly catalogProducts: CatalogProductsService,
  ) {}

  async chat(user: { id: string; role: Role }, dto: ChatAiAssistantDto) {
    const message = dto.message.trim();
    if (!message) throw new BadRequestException('El mensaje es obligatorio');

    const context = this.normalizeContext(dto.context);
    const currentUserName = await this.getCurrentUserPreferredName(user.id);
    const effectiveDto = { ...dto, context };

    if (!this.canAccessContext(user.role, context)) {
      return this.finalizeChatResponse(user, effectiveDto, {
        source: 'policy',
        content: AiAssistantService.unauthorizedMessage,
        citations: [],
        denied: true,
      }, []);
    }

    // Hard deny for common secret/credential extraction attempts.
    if (this.isForbiddenSecretRequest(message)) {
      return this.finalizeChatResponse(user, effectiveDto, {
        source: 'policy',
        content: AiAssistantService.unauthorizedMessage,
        citations: [],
        denied: true,
      }, []);
    }

    if (this.isOtherUserSensitiveRequest(user, message, context)) {
      return this.finalizeChatResponse(user, effectiveDto, {
        source: 'policy',
        content: 'Puedo ayudarte con tu propia información, pero no puedo revelar datos personales, de nómina, contrato o perfil de otro usuario.',
        citations: [],
        denied: true,
      }, []);
    }

    const knowledge = await this.buildKnowledge(user, effectiveDto);
    this.logDebug('ai.chat.context', context);
    this.logDebug('ai.chat.knowledge', knowledge.map((k) => ({ id: k.id, title: k.title, module: k.module })));

    if (knowledge.length === 0) {
      return this.finalizeChatResponse(user, effectiveDto, {
        source: 'rules-only',
        content: this.personalizeContent(AiAssistantService.notEnoughDataMessage, currentUserName),
        citations: [],
      }, knowledge);
    }

    if (this.shouldUseDeterministicLookupAnswer(message, context, knowledge)) {
      return this.finalizeChatResponse(
        user,
        effectiveDto,
        this.buildRuleOnlyFallback(message, knowledge, currentUserName),
        knowledge,
      );
    }

    const runtime = await this.getOpenAiRuntimeConfig();
    if (!runtime.apiKey) {
      return this.finalizeChatResponse(
        user,
        effectiveDto,
        this.buildRuleOnlyFallback(message, knowledge, currentUserName),
        knowledge,
      );
    }

    const safeHistory = this.normalizeHistory(dto.history).slice(-8);

    const systemPrompt =
      `Eres el asistente administrativo interno de ${runtime.companyName} dentro de la app FULLTECH. ` +
      'Debes responder de forma humana, clara y profesional. ' +
      `${currentUserName ? `Debes dirigirte al usuario actual por su nombre, ${currentUserName}, cuando sea natural hacerlo. ` : ''}` +
      'Nunca menciones memoria interna, contexto interno, tokens, ranking, fuentes tecnicas, historiales internos ni mecanismos del sistema. Si recuerdas algo util, usalo con naturalidad sin explicar como lo recordaste. ' +
      'REGLAS DE SEGURIDAD: 1) solo puedes usar el conocimiento interno enviado por el sistema; 2) no inventes; 3) no uses conocimiento externo; 4) no reveles datos privados de otros usuarios; 5) si el conocimiento incluye datos del usuario autenticado sobre sí mismo, sí puedes responderlos; 6) nunca conviertas una consulta del propio usuario en una negativa si el sistema ya envió sus datos autorizados; 7) si falta permiso o datos, dilo con respeto. ' +
      'REGLAS DE CALIDAD: si la respuesta es larga, resume al inicio; si el usuario pide pasos, responde paso a paso. ' +
      'Devuelve únicamente JSON válido.';

    const userPrompt =
      `${JSON.stringify({ message, context, history: safeHistory, knowledge, currentUserName })}\n\n` +
      'Devuelve exactamente este JSON: ' +
      '{"content":"string","citations":[{"id":"string","module":"string","category":"string","title":"string"}],"denied":false}. ' +
      'Reglas estrictas: ' +
      '1) si respondes algo útil basado en conocimiento enviado, citations no puede ir vacío; ' +
      '2) no incluyas citas inventadas; ' +
      '3) si el usuario pide información no autorizada de un tercero, usa denied=true y content debe explicar que no tiene permisos; ' +
      '4) si el usuario pregunta por su propia información y existe conocimiento del usuario actual, responde con esos datos y denied=false; ' +
      '5) si no hay información suficiente, denied=false y content debe pedir más contexto.';

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
      return this.finalizeChatResponse(user, effectiveDto, {
        source: 'policy',
        content: this.isUnauthorizedMessage(content) ? content : AiAssistantService.unauthorizedMessage,
        citations: [],
        denied: true,
      }, knowledge);
    }

    // If the model returned something useful but without citations, fall back to deterministic retrieval.
    if (citations.length === 0) {
      return this.finalizeChatResponse(
        user,
        effectiveDto,
        this.buildRuleOnlyFallback(message, knowledge, currentUserName),
        knowledge,
      );
    }

    return this.finalizeChatResponse(user, effectiveDto, {
      source: 'openai',
      content: this.personalizeContent(content, currentUserName),
      citations,
      denied: false,
    }, knowledge);
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
        return true;
      case 'ventas':
        return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR]);
      case 'cotizaciones':
        return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.MARKETING]);
      case 'clientes':
        return true;
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
    return true;
  }

  private shouldUseDeterministicLookupAnswer(
    message: string,
    context: NormalizedAiContext,
    knowledge: KnowledgeRecord[],
  ) {
    const tokens = new Set(this.tokenize(`${message} ${context.module} ${context.screenName ?? ''}`));
    const hasMatchedClient = knowledge.some((item) => item.id.startsWith('app-data:client-match:'));
    const hasMatchedCatalog = knowledge.some(
      (item) => item.id === 'app-data:catalog-search' || item.id.startsWith('app-data:product-match:'),
    );
    const hasManualKnowledge = knowledge.some(
      (item) => item.module === 'manual-interno' || item.category === 'politicas',
    );
    const hasContractKnowledge = knowledge.some(
      (item) => item.id.startsWith('app-data:contract:') || item.id.startsWith('app-data:contract-match:'),
    );
    const hasSelfKnowledge = knowledge.some(
      (item) => item.id.startsWith('app-data:self:') || item.id.startsWith('app-data:contract:'),
    );
    const explicitClientLookup =
      hasMatchedClient ||
      this.hasAnyToken(tokens, ['cliente', 'clientes', 'nombre', 'telefono', 'teléfono', 'movimientos', 'ventas', 'servicios']);
    const explicitCatalogLookup =
      hasMatchedCatalog ||
      this.hasAnyToken(tokens, ['producto', 'productos', 'catalogo', 'catálogo', 'precio', 'stock', 'inventario']);
    const explicitManualLookup =
      hasManualKnowledge ||
      this.hasAnyToken(tokens, [
        'manual',
        'norma',
        'normas',
        'regla',
        'reglas',
        'politica',
        'política',
        'politicas',
        'políticas',
        'protocolo',
        'protocolos',
      ]);
    const explicitContractLookup =
      hasContractKnowledge ||
      this.hasAnyToken(tokens, [
        'contrato',
        'contratos',
        'laboral',
        'trabajo',
        'salario',
        'sueldo',
        'pago',
        'frecuencia',
        'clausula',
        'cláusula',
        'firma',
        'nomina',
        'nómina',
      ]);
    const explicitSelfLookup = hasSelfKnowledge || this.isSelfInfoRequest(message, context);

    return explicitClientLookup || explicitCatalogLookup || explicitManualLookup || explicitContractLookup || explicitSelfLookup;
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
      take: 260,
    });

    const manualKnowledge = manualEntries.map((entry) => this.toManualKnowledge(entry));
    const staticHelp = this.buildStaticModuleHelp(manualEntries.length);
    const persistentMemory = await this.buildPersistentMemoryKnowledge(user, dto);
    const authorizedData = [
      ...(await this.buildAuthorizedDataKnowledge(user, dto)),
      ...persistentMemory,
    ];

    const all = [
      ...manualKnowledge,
      ...staticHelp,
      ...authorizedData,
    ];

    return this.selectKnowledgeForPrompt({
      prompt: dto.message,
      context: dto.context,
      manualKnowledge,
      staticHelp,
      authorizedData,
      all,
    });
  }

  private buildStaticModuleHelp(manualCount: number): KnowledgeRecord[] {
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
        'app-help:manual-coverage',
        'manual-interno',
        'guia-app',
        'Cobertura del Manual Interno',
        `Actualmente el sistema tiene ${manualCount} entradas publicadas del Manual Interno disponibles para este asistente según permisos y rol.`,
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
    const wantsClientsByIntent = this.isLikelyClientLookup(dto, tokens);
    const wantsCatalogByIntent = this.isLikelyCatalogLookup(dto, tokens);

    const wantsClients = includeModuleContext || wantsClientsByIntent || this.hasAnyToken(tokens, ['cliente', 'clientes']);
    const wantsCatalog = includeModuleContext || wantsCatalogByIntent || this.hasAnyToken(tokens, ['producto', 'productos', 'catalogo', 'catálogo', 'precio', 'precios']);
    const wantsContracts = includeModuleContext || this.hasAnyToken(tokens, ['contrato', 'nomina', 'nómina', 'salario', 'clausula', 'cláusula']);
    const wantsQuotes = includeModuleContext || this.hasAnyToken(tokens, ['cotizacion', 'cotizaciones', 'ticket', 'propuesta']);
    const wantsSales = includeModuleContext || this.hasAnyToken(tokens, ['venta', 'ventas', 'comision', 'comisión']);
    const wantsOperations = includeModuleContext || this.hasAnyToken(tokens, ['servicio', 'servicios', 'operacion', 'operaciones', 'garantia', 'garantía']);
    const wantsAccounting = includeModuleContext || this.hasAnyToken(tokens, ['contabilidad', 'cierre', 'cierres', 'deposito', 'depósito', 'factura', 'pago']);
    const wantsSelf = includeModuleContext || this.isSelfInfoRequest(dto.message, dto.context);
    const wantsAdaptiveLearning = includeModuleContext || this.isAdaptiveLearningQuestion(dto.message, dto.context);

    const knowledge: KnowledgeRecord[] = [];

    if (wantsAdaptiveLearning) {
      const adaptiveKnowledge = await this.buildAdaptiveKnowledge(user);
      knowledge.push(...adaptiveKnowledge);
    }

    const conversationKnowledge = this.buildConversationLearningKnowledge(dto);
    knowledge.push(...conversationKnowledge);

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

  private isLikelyCatalogLookup(dto: ChatAiAssistantDto, tokens: Set<string>) {
    const module = this.normalizeModuleKey(dto.context.module);
    const searchTerms = this.extractMeaningfulQueryTerms(dto.message, {
      limit: 6,
      extraNoise: [
        'conocer',
        'conoce',
        'conoces',
        'saber',
        'sabe',
        'empresa',
        'empresas',
        'emprs',
        'fulltech',
        'todos',
        'todas',
        'producto',
        'productos',
        'catalogo',
        'catalogos',
        'catálogo',
        'precio',
        'precios',
        'disponible',
        'disponibles',
        'disponibilidad',
        'inventario',
        'stock',
      ],
    });

    if (['catalogo', 'cotizaciones', 'ventas'].includes(module) && searchTerms.length > 0) {
      return true;
    }

    return this.hasAnyToken(tokens, [
      'producto',
      'productos',
      'catalogo',
      'catálogo',
      'precio',
      'precios',
      'stock',
      'inventario',
      'disponible',
      'disponibilidad',
      'hay',
      'tienen',
      'busca',
      'buscame',
      'muestrame',
      'muéstrame',
      'cuesta',
      'vale',
    ]) && searchTerms.length > 0;
  }

  private isLikelyClientLookup(dto: ChatAiAssistantDto, tokens: Set<string>) {
    const module = this.normalizeModuleKey(dto.context.module);
    const searchTerms = this.extractMeaningfulQueryTerms(dto.message, {
      limit: 6,
      extraNoise: [
        'cliente',
        'clientes',
        'telefono',
        'teléfono',
        'correo',
        'email',
        'direccion',
        'dirección',
        'contacto',
      ],
    });
    const phoneTerms = this.extractNumericQueryTerms(dto.message);

    if (['clientes', 'operaciones', 'ventas', 'cotizaciones'].includes(module)) {
      return searchTerms.length > 0 || phoneTerms.length > 0;
    }

    return this.hasAnyToken(tokens, [
      'cliente',
      'clientes',
      'telefono',
      'teléfono',
      'correo',
      'email',
      'direccion',
      'dirección',
      'contacto',
      'whatsapp',
    ]) || phoneTerms.length > 0;
  }

  private isAdaptiveLearningQuestion(message: string, context: NormalizedAiContext) {
    const tokens = new Set(this.tokenize(`${message} ${context.module} ${context.screenName ?? ''}`));
    return this.hasAnyToken(tokens, [
      'aprender',
      'aprende',
      'aprendiendo',
      'aprendizaje',
      'crecer',
      'creciendo',
      'actualizar',
      'actualizando',
      'datos',
      'tablas',
      'conocimiento',
      'memoria',
      'sistema',
    ]);
  }

  private async buildAdaptiveKnowledge(user: { id: string; role: Role }): Promise<KnowledgeRecord[]> {
    const ownerId = await this.resolveCompanyOwnerId(user.id);

    const clientWhere: Prisma.ClientWhereInput =
      user.role === Role.TECNICO
        ? {
            isDeleted: false,
            OR: [
              { ownerId: user.id },
              { services: { some: { OR: [{ technicianId: user.id }, { createdByUserId: user.id }] } } },
            ],
          }
        : { isDeleted: false };
    const salesWhere: Prisma.SaleWhereInput = user.role === Role.ADMIN ? {} : { userId: user.id };
    const servicesWhere: Prisma.ServiceWhereInput =
      user.role === Role.ADMIN || user.role === Role.ASISTENTE
        ? { isDeleted: false }
        : user.role === Role.VENDEDOR
          ? { isDeleted: false, createdByUserId: user.id }
          : user.role === Role.TECNICO
            ? { isDeleted: false, assignments: { some: { userId: user.id } } }
            : { id: '__none__' };
    const quotesWhere: Prisma.CotizacionWhereInput = user.role === Role.ADMIN ? {} : { createdByUserId: user.id };

    const [
      manualCount,
      clientCount,
      salesCount,
      serviceCount,
      quoteCount,
      latestManual,
      latestClient,
      latestSale,
      latestService,
      latestQuote,
      fallbackProductCount,
    ] = await this.prisma.$transaction([
      this.prisma.companyManualEntry.count({ where: { ownerId, published: true } }),
      this.prisma.client.count({ where: clientWhere }),
      this.prisma.sale.count({ where: salesWhere }),
      this.prisma.service.count({ where: servicesWhere }),
      this.prisma.cotizacion.count({ where: quotesWhere }),
      this.prisma.companyManualEntry.findFirst({
        where: { ownerId, published: true },
        orderBy: { updatedAt: 'desc' },
        select: { title: true, updatedAt: true },
      }),
      this.prisma.client.findFirst({
        where: clientWhere,
        orderBy: { updatedAt: 'desc' },
        select: { nombre: true, updatedAt: true },
      }),
      this.prisma.sale.findFirst({
        where: salesWhere,
        orderBy: { updatedAt: 'desc' },
        select: { saleDate: true, customer: { select: { nombre: true } } },
      }),
      this.prisma.service.findFirst({
        where: servicesWhere,
        orderBy: { updatedAt: 'desc' },
        select: { title: true, updatedAt: true },
      }),
      this.prisma.cotizacion.findFirst({
        where: quotesWhere,
        orderBy: { updatedAt: 'desc' },
        select: { customerName: true, updatedAt: true },
      }),
      this.prisma.product.count(),
    ]);

    let productCount = fallbackProductCount;
    try {
      const liveCatalog = await this.catalogProducts.findAll();
      if (liveCatalog.total > 0) {
        productCount = liveCatalog.total;
      }
    } catch {
      productCount = fallbackProductCount;
    }

    const summary = [
      'El asistente usa conocimiento vivo del sistema, no solo respuestas estaticas.',
      'Por eso su contexto crece cuando aumentan los datos autorizados y las entradas publicadas del Manual Interno.',
      `Ahora mismo puede apoyarse en ${manualCount} normas publicadas, ${clientCount} clientes, ${productCount} productos, ${salesCount} ventas, ${serviceCount} servicios y ${quoteCount} cotizaciones visibles para tu alcance.`,
      'Cada nueva consulta vuelve a leer estos datos y por eso el asistente puede crecer junto con las tablas del sistema.',
    ].join(' ');

    const recents = [
      latestManual ? `Manual actualizado recientemente: ${latestManual.title} (${this.formatKnowledgeDate(latestManual.updatedAt)}).` : null,
      latestClient ? `Cliente reciente: ${latestClient.nombre} (${this.formatKnowledgeDate(latestClient.updatedAt)}).` : null,
      latestSale ? `Venta reciente: ${latestSale.customer?.nombre ?? 'N/D'} (${this.formatKnowledgeDate(latestSale.saleDate)}).` : null,
      latestService ? `Servicio reciente: ${latestService.title} (${this.formatKnowledgeDate(latestService.updatedAt)}).` : null,
      latestQuote ? `Cotizacion reciente: ${latestQuote.customerName} (${this.formatKnowledgeDate(latestQuote.updatedAt)}).` : null,
    ].filter((item): item is string => !!item);

    return [
      this.createAppKnowledgeRecord(
        'app-data:growth-summary',
        'general',
        'dato-autorizado',
        'Base de conocimiento viva del asistente',
        summary,
      ),
      this.createAppKnowledgeRecord(
        'app-data:growth-recent',
        'general',
        'dato-autorizado',
        'Actividad reciente del sistema',
        recents.length > 0
          ? recents.join(' ')
          : 'No hay cambios recientes resumidos en este momento, pero el asistente seguira leyendo datos nuevos en cada consulta.',
      ),
      this.createAppKnowledgeRecord(
        'app-data:growth-policy',
        'general',
        'politica-app',
        'Como crece el conocimiento del asistente',
        'El asistente puede crecer con datos nuevos del sistema, productos nuevos, clientes nuevos, operaciones nuevas y nuevas entradas publicadas del Manual Interno. La conversacion actual le aporta memoria reciente, pero las reglas oficiales y los datos autorizados tienen prioridad.',
      ),
    ];
  }

  private buildConversationLearningKnowledge(dto: ChatAiAssistantDto): KnowledgeRecord[] {
    const history = this.normalizeHistory(dto.history).slice(-12);
    if (history.length === 0) return [];

    const recentUserMessages = history.filter((item) => item.role === 'user').slice(-5);
    const recentAssistantMessages = history.filter((item) => item.role === 'assistant').slice(-3);
    const repeatedTopics = this.extractMeaningfulQueryTerms(
      recentUserMessages.map((item) => item.content).join(' '),
      { limit: 8 },
    );

    const parts = [
      'Contexto acumulado de la conversacion actual.',
      recentUserMessages.length > 0
        ? `Ultimas solicitudes del usuario: ${recentUserMessages.map((item) => this.buildExcerpt(item.content)).join(' | ')}`
        : null,
      repeatedTopics.length > 0
        ? `Temas relevantes repetidos en este hilo: ${repeatedTopics.join(', ')}.`
        : null,
      recentAssistantMessages.length > 0
        ? `Ultimas respuestas del asistente: ${recentAssistantMessages.map((item) => this.buildExcerpt(item.content)).join(' | ')}`
        : null,
      'Este contexto funciona como memoria reciente dentro del mismo hilo.',
    ].filter((item): item is string => !!item);

    return [
      this.createAppKnowledgeRecord(
        'app-data:conversation-context',
        'general',
        'dato-autorizado',
        'Memoria reciente de la conversacion',
        parts.join(' '),
      ),
    ];
  }

  private async buildPersistentMemoryKnowledge(
    user: { id: string; role: Role },
    dto: ChatAiAssistantDto,
  ): Promise<KnowledgeRecord[]> {
    try {
      const ownerId = await this.resolveCompanyOwnerId(user.id);
      const memoryRows = await this.prisma.$queryRaw<PersistedAssistantMemoryRow[]>(Prisma.sql`
        SELECT
          id::text AS id,
          module,
          scope,
          topic_key AS "topicKey",
          title,
          summary,
          keywords,
          source_count AS "sourceCount",
          last_source_at AS "lastSourceAt",
          "createdAt",
          "updatedAt"
        FROM ai_assistant_memories
        WHERE owner_id = ${ownerId}
          AND user_id = ${user.id}
        ORDER BY last_source_at DESC
        LIMIT 24
      `);

      const recentTurns = await this.prisma.$queryRaw<PersistedConversationTurnRow[]>(Prisma.sql`
        SELECT
          user_message AS "userMessage",
          assistant_response AS "assistantResponse",
          module,
          "createdAt"
        FROM ai_assistant_conversation_turns
        WHERE owner_id = ${ownerId}
          AND user_id = ${user.id}
        ORDER BY "createdAt" DESC
        LIMIT 4
      `);

      const tokens = new Set(this.tokenize(`${dto.message} ${dto.context.module ?? ''} ${dto.context.screenName ?? ''}`));
      const rankedMemories = memoryRows
        .map((row) => {
          const keywordText = this.parseStoredKeywords(row.keywords).join(' ');
          const haystack = `${row.title} ${row.summary} ${row.module} ${row.topicKey} ${keywordText}`;
          const rowTokens = new Set(this.tokenize(haystack));
          let score = 0;
          for (const token of tokens) {
            if (rowTokens.has(token)) score += token.length >= 5 ? 2 : 1;
          }
          if (this.normalizeModuleKey(row.module) === this.normalizeModuleKey(dto.context.module)) score += 3;
          if (score === 0 && this.normalizeModuleKey(row.module) === this.normalizeModuleKey(dto.context.module)) score = 1;
          return { row, score };
        })
        .filter((item) => item.score > 0)
        .sort((a, b) => b.score - a.score)
        .slice(0, 6)
        .map((item) => item.row);

      const knowledge = rankedMemories.map((row) => this.createAppKnowledgeRecord(
        `app-memory:${row.id}`,
        row.module || 'general',
        'memoria',
        row.title,
        `${row.summary}\n\nFuentes acumuladas: ${row.sourceCount}. Ultima actualizacion: ${this.formatKnowledgeDate(this.toDateValue(row.lastSourceAt))}.`,
      ));

      if (recentTurns.length > 0) {
        const lines = recentTurns.map((turn) => (
          `${this.formatKnowledgeDate(this.toDateValue(turn.createdAt))}: Usuario dijo "${this.buildExcerpt(turn.userMessage)}" y el asistente respondio "${this.buildExcerpt(turn.assistantResponse)}".`
        ));
        knowledge.push(
          this.createAppKnowledgeRecord(
            'app-memory:recent-turns',
            dto.context.module || 'general',
            'memoria',
            'Continuidad entre sesiones del asistente',
            lines.join(' '),
          ),
        );
      }

      return knowledge;
    } catch (error) {
      this.logDebug('ai.memory.read_skip', {
        message: error instanceof Error ? error.message : `${error}`,
      });
      return [];
    }
  }

  private async finalizeChatResponse(
    user: { id: string; role: Role },
    dto: ChatAiAssistantDto & { context: NormalizedAiContext },
    response: AiAssistantChatResponse,
    knowledge: KnowledgeRecord[],
  ) {
    await this.persistLearningArtifacts(user, dto, response, knowledge);
    return response;
  }

  private async persistLearningArtifacts(
    user: { id: string; role: Role },
    dto: ChatAiAssistantDto & { context: NormalizedAiContext },
    response: AiAssistantChatResponse,
    knowledge: KnowledgeRecord[],
  ) {
    try {
      const ownerId = await this.resolveCompanyOwnerId(user.id);
      const citationsJson = JSON.stringify(response.citations ?? []);

      await this.prisma.$executeRaw(Prisma.sql`
        INSERT INTO ai_assistant_conversation_turns (
          id,
          owner_id,
          user_id,
          module,
          route,
          entity_type,
          entity_id,
          user_message,
          assistant_response,
          response_source,
          denied,
          citations,
          "createdAt"
        ) VALUES (
          gen_random_uuid(),
          ${ownerId},
          ${user.id},
          ${dto.context.module || 'general'},
          ${dto.context.route ?? null},
          ${dto.context.entityType ?? null},
          ${dto.context.entityId ?? null},
          ${dto.message},
          ${response.content},
          ${response.source},
          ${response.denied === true},
          CAST(${citationsJson} AS JSONB),
          CURRENT_TIMESTAMP
        )
      `);

      const notes = this.buildPersistentMemoryNotes(dto, response, knowledge);
      for (const note of notes) {
        await this.upsertPersistentMemory(ownerId, user.id, note);
      }
    } catch (error) {
      this.logDebug('ai.memory.persist_skip', {
        message: error instanceof Error ? error.message : `${error}`,
      });
    }
  }

  private buildPersistentMemoryNotes(
    dto: ChatAiAssistantDto & { context: NormalizedAiContext },
    response: AiAssistantChatResponse,
    knowledge: KnowledgeRecord[],
  ): AssistantMemoryNote[] {
    const module = dto.context.module || 'general';
    const moduleLabel = this.describeMemoryModule(module);
    const userTerms = this.extractMeaningfulQueryTerms(dto.message, { limit: 6 });
    const responseTerms = this.extractMeaningfulQueryTerms(response.content, {
      limit: 6,
      extraNoise: ['encontre', 'informacion', 'detalle', 'detalles', 'resumen', 'consulta'],
    });
    const mergedTerms = [...new Set([...userTerms, ...responseTerms])].slice(0, 10);
    const noteBody = `Consulta: ${this.buildExcerpt(dto.message)} Respuesta: ${this.buildExcerpt(response.content)}`;
    const notes: AssistantMemoryNote[] = [
      {
        scope: 'user',
        module,
        topicKey: `module:${module}`,
        title: `Memoria reciente del modulo ${moduleLabel}`,
        summary: noteBody,
        keywords: mergedTerms,
      },
    ];

    if (dto.context.entityType && dto.context.entityId) {
      notes.push({
        scope: 'user',
        module,
        topicKey: `entity:${dto.context.entityType}:${dto.context.entityId}`,
        title: `Seguimiento de ${dto.context.entityType}`,
        summary: `Entidad consultada dentro del modulo ${moduleLabel}. ${noteBody}`,
        keywords: [dto.context.entityType, dto.context.entityId, ...mergedTerms].slice(0, 10),
      });
    }

    const citedTitles = response.citations.map((item) => item.title).filter((item) => item.trim().length > 0);
    if (mergedTerms.length > 0) {
      notes.push({
        scope: 'user',
        module,
        topicKey: `topic:${module}:${mergedTerms.slice(0, 3).join('-')}`,
        title: `Tema recurrente en ${moduleLabel}`,
        summary: citedTitles.length > 0
          ? `${noteBody} Referencias usadas: ${citedTitles.slice(0, 3).join(', ')}.`
          : noteBody,
        keywords: [...mergedTerms, ...citedTitles.flatMap((item) => this.tokenize(item))].slice(0, 12),
      });
    }

    const filtered = notes.filter((note, index, all) => all.findIndex((item) => item.topicKey === note.topicKey) === index);
    return filtered.slice(0, 3);
  }

  private async upsertPersistentMemory(ownerId: string, userId: string, note: AssistantMemoryNote) {
    const existing = await this.prisma.$queryRaw<Array<{
      summary: string;
      keywords: Prisma.JsonValue | null;
      sourceCount: number;
    }>>(Prisma.sql`
      SELECT summary, keywords, source_count AS "sourceCount"
      FROM ai_assistant_memories
      WHERE owner_id = ${ownerId}
        AND user_id = ${userId}
        AND scope = ${note.scope}
        AND topic_key = ${note.topicKey}
      LIMIT 1
    `);

    const mergedSummary = this.mergeMemorySummary(existing[0]?.summary ?? '', note.summary);
    const mergedKeywords = this.mergeMemoryKeywords(this.parseStoredKeywords(existing[0]?.keywords ?? null), note.keywords);
    const mergedKeywordsJson = JSON.stringify(mergedKeywords);

    if (existing.length > 0) {
      await this.prisma.$executeRaw(Prisma.sql`
        UPDATE ai_assistant_memories
        SET
          module = ${note.module},
          title = ${note.title},
          summary = ${mergedSummary},
          keywords = CAST(${mergedKeywordsJson} AS JSONB),
          source_count = source_count + 1,
          last_source_at = CURRENT_TIMESTAMP,
          "updatedAt" = CURRENT_TIMESTAMP
        WHERE owner_id = ${ownerId}
          AND user_id = ${userId}
          AND scope = ${note.scope}
          AND topic_key = ${note.topicKey}
      `);
      return;
    }

    await this.prisma.$executeRaw(Prisma.sql`
      INSERT INTO ai_assistant_memories (
        id,
        owner_id,
        user_id,
        scope,
        module,
        topic_key,
        title,
        summary,
        keywords,
        source_count,
        last_source_at,
        "createdAt",
        "updatedAt"
      ) VALUES (
        gen_random_uuid(),
        ${ownerId},
        ${userId},
        ${note.scope},
        ${note.module},
        ${note.topicKey},
        ${note.title},
        ${mergedSummary},
        CAST(${mergedKeywordsJson} AS JSONB),
        1,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      )
    `);
  }

  private mergeMemorySummary(existingSummary: string, incomingSummary: string) {
    const items = [
      ...existingSummary.split('\n').map((item) => item.trim()).filter((item) => item.length > 0),
      incomingSummary.trim(),
    ];
    const deduped: string[] = [];
    const seen = new Set<string>();

    for (const item of items) {
      const key = item.toLowerCase();
      if (!key || seen.has(key)) continue;
      seen.add(key);
      deduped.push(item);
    }

    let trimmed = deduped.slice(-6);
    while (trimmed.join('\n').length > 900 && trimmed.length > 1) {
      trimmed = trimmed.slice(1);
    }
    return trimmed.join('\n');
  }

  private mergeMemoryKeywords(existing: string[], incoming: string[]) {
    return [...new Set([...existing, ...incoming].map((item) => item.trim()).filter((item) => item.length >= 3))].slice(0, 14);
  }

  private parseStoredKeywords(raw: Prisma.JsonValue | null) {
    if (!raw || !Array.isArray(raw)) return [];
    return raw.map((item) => `${item}`.trim()).filter((item) => item.length > 0);
  }

  private describeMemoryModule(module: string) {
    switch (this.normalizeModuleKey(module)) {
      case 'manual-interno':
        return 'Manual Interno';
      case 'catalogo':
        return 'Catalogo';
      case 'clientes':
        return 'Clientes';
      case 'operaciones':
        return 'Operaciones';
      case 'ventas':
        return 'Ventas';
      case 'cotizaciones':
        return 'Cotizaciones';
      case 'nomina':
        return 'Nomina';
      case 'profile':
        return 'Perfil';
      default:
        return 'General';
    }
  }

  private toDateValue(value: Date | string | null) {
    if (!value) return null;
    if (value instanceof Date) return value;
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
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
      raw.includes('mi cuenta') ||
      raw.includes('mis datos') ||
      raw.includes('mis pagos') ||
      raw.includes('mi contrato') ||
      raw.includes('mi salario') ||
      raw.includes('mi sueldo') ||
      raw.includes('de mi')
    );
  }

  private isOtherUserSensitiveRequest(
    user: { id: string; role: Role },
    message: string,
    context: NormalizedAiContext,
  ) {
    const targetEntityType = (context.entityType ?? '').trim().toLowerCase();
    const targetEntityId = (context.entityId ?? '').trim();
    const referencesAnotherUser = targetEntityType === 'user' && targetEntityId.length > 0 && targetEntityId !== user.id;

    if (!referencesAnotherUser) return false;

    const tokens = new Set(this.tokenize(`${message} ${context.module} ${context.screenName ?? ''}`));
    return this.hasAnyToken(tokens, [
      'usuario',
      'usuarios',
      'empleado',
      'empleados',
      'perfil',
      'correo',
      'email',
      'telefono',
      'teléfono',
      'rol',
      'nomina',
      'nómina',
      'contrato',
      'salario',
      'sueldo',
      'pago',
      'pagos',
      'datos',
      'informacion',
      'información',
    ]);
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
      this.createAppKnowledgeRecord(
        'app-data:self:privacy-scope',
        'profile',
        'politica-app',
        'Alcance de datos del usuario actual',
        'El asistente sí puede responder datos del usuario autenticado que está haciendo la consulta cuando esos datos fueron enviados como conocimiento autorizado. No puede responder datos personales de terceros.',
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

  private selectKnowledgeForPrompt(input: {
    prompt: string;
    context: NormalizedAiContext;
    manualKnowledge: KnowledgeRecord[];
    staticHelp: KnowledgeRecord[];
    authorizedData: KnowledgeRecord[];
    all: KnowledgeRecord[];
  }): KnowledgeRecord[] {
    const rankedAll = this.rankKnowledgeForPrompt(input.prompt, input.context, input.all);
    const rankedManual = this.rankKnowledgeForPrompt(input.prompt, input.context, input.manualKnowledge);
    const rankedAuthorized = this.rankKnowledgeForPrompt(input.prompt, input.context, input.authorizedData);
    const rankedAuthorizedVisible = rankedAuthorized.filter((item) => this.isUserVisibleKnowledge(item));
    const rankedAuthorizedInternal = rankedAuthorized.filter((item) => !this.isUserVisibleKnowledge(item));
    const normalizedModule = this.normalizeModuleKey(input.context.module);
    const isSelfRequest = this.isSelfInfoRequest(input.prompt, input.context);
    const prioritizedSelfKnowledge = rankedAuthorizedVisible.filter(
      (item) =>
        item.id.startsWith('app-data:self:') ||
        item.id.startsWith('app-data:contract:') ||
        item.id === 'app-data:contracts-policy',
    );
    const remainingAuthorizedVisible = rankedAuthorizedVisible.filter(
      (item) => !prioritizedSelfKnowledge.some((candidate) => candidate.id === item.id),
    );
    const wantsManualDepth =
      normalizedModule === 'manual-interno' ||
      this.hasAnyToken(
        new Set(this.tokenize(`${input.prompt} ${input.context.screenName ?? ''}`)),
        ['manual', 'interno', 'politica', 'política', 'protocolo', 'regla', 'reglas'],
      );

    const limit = wantsManualDepth ? 28 : 20;
    const selected: KnowledgeRecord[] = [];
    const seenIds = new Set<string>();

    const addRecords = (items: KnowledgeRecord[], maxCount?: number) => {
      let added = 0;
      for (const item of items) {
        if (seenIds.has(item.id)) continue;
        selected.push(item);
        seenIds.add(item.id);
        added += 1;
        if (selected.length >= limit) return;
        if (maxCount != null && added >= maxCount) return;
      }
    };

    if (isSelfRequest) {
      addRecords(prioritizedSelfKnowledge, 6);
    }
    addRecords(
      input.staticHelp.filter(
        (item) => item.module === 'seguridad' || item.module === 'manual-interno',
      ),
      3,
    );
    addRecords(remainingAuthorizedVisible, wantsManualDepth ? 8 : 10);
    addRecords(
      rankedManual.filter(
        (item) =>
          this.normalizeModuleKey(item.module) === normalizedModule ||
          item.module === 'general' ||
          item.category === 'politicas',
      ),
      wantsManualDepth ? 14 : 8,
    );
    addRecords(rankedManual, wantsManualDepth ? 10 : 6);
    addRecords(rankedAuthorizedInternal, 3);
    addRecords(rankedAll, limit);

    return selected.slice(0, limit);
  }

  private async buildClientKnowledge(user: { id: string; role: Role }, dto: ChatAiAssistantDto): Promise<KnowledgeRecord[]> {
    const isAdmin = user.role === Role.ADMIN;

    const accessibleWhere: Prisma.ClientWhereInput =
      user.role === Role.TECNICO
        ? {
            isDeleted: false,
            OR: [
              { ownerId: user.id },
              { services: { some: { OR: [{ technicianId: user.id }, { createdByUserId: user.id }] } } },
            ],
          }
        : { isDeleted: false };

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
    const searchTerms = this.extractMeaningfulQueryTerms(dto.message, {
      limit: 6,
      extraNoise: [
        'cliente',
        'clientes',
        'nombre',
        'nombres',
        'llama',
        'llamado',
        'llamada',
        'coincidencia',
        'coincidencias',
        'verifica',
        'verificar',
        'existe',
        'tiene',
        'tengan',
        'algun',
        'alguna',
        'algunas',
        'algunos',
        'telefono',
        'teléfono',
        'correo',
        'email',
        'direccion',
        'dirección',
        'contacto',
        'muestrame',
        'muéstrame',
        'busca',
        'buscame',
        'dime',
      ],
    });
    const phoneTerms = this.extractNumericQueryTerms(dto.message);

    if (!entityId && searchTerms.length === 0 && phoneTerms.length === 0) return base;

    if (!entityId) {
      const searchWhere: Prisma.ClientWhereInput = {
        ...accessibleWhere,
        OR: [
          ...searchTerms.map((term) => ({ nombre: { contains: term, mode: 'insensitive' as const } })),
          ...searchTerms.map((term) => ({ email: { contains: term, mode: 'insensitive' as const } })),
          ...searchTerms.map((term) => ({ direccion: { contains: term, mode: 'insensitive' as const } })),
          ...searchTerms.map((term) => ({ notas: { contains: term, mode: 'insensitive' as const } })),
          ...phoneTerms.map((term) => ({ telefono: { contains: term, mode: 'insensitive' as const } })),
          ...phoneTerms.map((term) => ({ phoneNormalized: { contains: term } })),
        ],
      };

      const matchingClients = await this.prisma.client.findMany({
        where: searchWhere,
        select: {
          id: true,
          nombre: true,
          telefono: true,
          email: true,
          direccion: true,
          lastActivityAt: true,
        },
        take: 12,
        orderBy: [{ lastActivityAt: 'desc' }, { nombre: 'asc' }],
      });

      if (matchingClients.length === 0) {
        base.push(
          this.createAppKnowledgeRecord(
            'app-data:clients-search-none',
            'clientes',
            'dato-autorizado',
            'Cliente no encontrado',
            `No encontré clientes autorizados que coincidan con: ${[...searchTerms, ...phoneTerms].join(', ')}.`,
          ),
        );
        return base;
      }

      const rankedClients = matchingClients
        .map((client) => {
          let score = 0;
          for (const term of searchTerms) {
            const haystack = `${client.nombre} ${client.email ?? ''} ${client.direccion ?? ''}`.toLowerCase();
            if (client.nombre.toLowerCase().includes(term)) {
              score += 3;
            } else if (haystack.includes(term)) {
              score += 1;
            }
          }
          for (const term of phoneTerms) {
            const haystack = `${client.telefono}`.replace(/\D+/g, '');
            if (haystack.includes(term)) score += 4;
          }
          return { client, score };
        })
        .sort((a, b) => b.score - a.score || a.client.nombre.localeCompare(b.client.nombre))
        .slice(0, 5)
        .map(({ client }) => client);

      const detailedMatches = await Promise.all(
        rankedClients.slice(0, 3).map(async (client) => {
          const [salesAgg, servicesAgg, quotesAgg, latestSale, latestService, latestQuote] = await this.prisma.$transaction([
            this.prisma.sale.aggregate({
              where: { customerId: client.id, isDeleted: false },
              _count: { _all: true },
              _sum: { totalSold: true },
              _max: { saleDate: true },
            }),
            this.prisma.service.aggregate({
              where: { customerId: client.id, isDeleted: false },
              _count: { _all: true },
              _max: { updatedAt: true },
            }),
            this.prisma.cotizacion.aggregate({
              where: { customerId: client.id },
              _count: { _all: true },
              _sum: { total: true },
              _max: { updatedAt: true },
            }),
            this.prisma.sale.findFirst({
              where: { customerId: client.id, isDeleted: false },
              orderBy: { saleDate: 'desc' },
              select: { saleDate: true, totalSold: true },
            }),
            this.prisma.service.findFirst({
              where: { customerId: client.id, isDeleted: false },
              orderBy: { updatedAt: 'desc' },
              select: { updatedAt: true, title: true, status: true, currentPhase: true },
            }),
            this.prisma.cotizacion.findFirst({
              where: { customerId: client.id },
              orderBy: { updatedAt: 'desc' },
              select: { updatedAt: true, total: true, customerName: true },
            }),
          ]);

          return this.createAppKnowledgeRecord(
            `app-data:client-match:${client.id}`,
            'clientes',
            'dato-autorizado',
            `Cliente encontrado: ${client.nombre}`,
            [
              `Cliente: ${client.nombre}`,
              (client.telefono ?? '').trim().length > 0 ? `Telefono: ${client.telefono}` : null,
              (client.email ?? '').trim().length > 0 ? `Email: ${client.email}` : null,
              (client.direccion ?? '').trim().length > 0 ? `Direccion: ${this.buildExcerpt(client.direccion ?? '')}` : null,
              client.lastActivityAt != null ? `Ultima actividad: ${client.lastActivityAt.toISOString().slice(0, 10)}` : null,
              `Movimientos: ${salesAgg._count._all} ventas, ${servicesAgg._count._all} servicios y ${quotesAgg._count._all} cotizaciones`,
              salesAgg._sum.totalSold != null ? `Total vendido: ${Number(salesAgg._sum.totalSold).toFixed(2)}` : null,
              latestSale != null ? `Ultima venta: ${latestSale.saleDate.toISOString().slice(0, 10)} por ${Number(latestSale.totalSold).toFixed(2)}` : null,
              latestService != null ? `Ultimo servicio: ${latestService.title} (${latestService.status} / fase ${latestService.currentPhase}) actualizado el ${latestService.updatedAt.toISOString().slice(0, 10)}` : null,
              latestQuote != null ? `Ultima cotizacion: ${Number(latestQuote.total).toFixed(2)} actualizada el ${latestQuote.updatedAt.toISOString().slice(0, 10)}` : null,
            ].filter((item): item is string => !!item).join('\n'),
          );
        }),
      );

      base.push(...detailedMatches);

      base.push(
        this.createAppKnowledgeRecord(
          'app-data:clients-search',
          'clientes',
          'dato-autorizado',
          `Clientes relacionados con "${[...searchTerms, ...phoneTerms].join(' ')}"`,
          rankedClients
            .map((client) => {
              const details: string[] = [];
              if ((client.telefono ?? '').trim().length > 0) details.push(`Tel: ${client.telefono}`);
              if ((client.email ?? '').trim().length > 0) details.push(`Email: ${client.email}`);
              if ((client.direccion ?? '').trim().length > 0) {
                details.push(`Dirección: ${this.buildExcerpt(client.direccion ?? '')}`);
              }
              if (client.lastActivityAt != null) {
                details.push(`Última actividad: ${client.lastActivityAt.toISOString().slice(0, 10)}`);
              }
              return `- ${client.nombre}${details.length === 0 ? '' : ` | ${details.join(' | ')}`}`;
            })
            .join('\n'),
        ),
      );

      return base;
    }

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
    const searchTokens = this.extractMeaningfulQueryTerms(dto.message, {
      limit: 6,
      extraNoise: [
        'hay',
        'tengo',
        'tienen',
        'producto',
        'productos',
        'disponible',
        'disponibles',
        'disponibilidad',
        'precio',
        'precios',
        'catalogo',
        'catalogos',
        'catálogo',
        'app',
        'quiero',
        'buscar',
        'busca',
        'buscame',
        'muestrame',
        'muéstrame',
        'necesito',
        'dime',
        'inventario',
        'stock',
      ],
    });
    const searchVariants = this.expandSearchTerms(searchTokens);

    let total = 0;
    let categoryLines = 'No hay categorías disponibles en el catálogo.';
    let catalogSource = 'LOCAL';
    let remoteProducts: Array<{
      id: string;
      nombre: string;
      descripcion: string | null;
      codigo: string | null;
      precio: number;
      stock: number | null;
      categoria: string | null;
      categoriaNombre: string | null;
    }> = [];

    try {
      const catalog = await this.catalogProducts.findAll();
      catalogSource = catalog.source;
      remoteProducts = catalog.items.map((item) => ({
        id: item.id,
        nombre: item.nombre,
        descripcion: item.descripcion,
        codigo: item.codigo,
        precio: item.precio,
        stock: item.stock,
        categoria: item.categoria,
        categoriaNombre: item.categoriaNombre,
      }));
      total = catalog.total;

      const categories = new Map<string, number>();
      for (const item of remoteProducts) {
        const category = (item.categoriaNombre ?? item.categoria ?? 'Sin categoría').trim() || 'Sin categoría';
        categories.set(category, (categories.get(category) ?? 0) + 1);
      }
      categoryLines = [...categories.entries()]
        .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
        .slice(0, 5)
        .map(([category, count]) => `- ${category}: ${count}`)
        .join('\n');
    } catch {
      total = await this.prisma.product.count();
      const topCategories = await this.prisma.product.groupBy({
        by: ['categoria'],
        _count: { categoria: true },
        orderBy: { _count: { categoria: 'desc' } },
        take: 5,
      });
      categoryLines = topCategories.length > 0
        ? topCategories
            .map((item) => `- ${item.categoria || 'Sin categoría'}: ${item._count.categoria}`)
            .join('\n')
        : categoryLines;
    }

    const result: KnowledgeRecord[] = [
      this.createAppKnowledgeRecord(
        'app-data:catalog-count',
        'catalogo',
        'dato-autorizado',
        'Resumen autorizado de catálogo',
        `Actualmente hay ${total} productos en el catálogo. Fuente activa para el asistente: ${catalogSource}.`,
      ),
      this.createAppKnowledgeRecord(
        'app-data:catalog-categories',
        'catalogo',
        'dato-autorizado',
        'Categorías principales del catálogo',
        categoryLines,
      ),
    ];

    if (searchTokens.length === 0) return result;

    const products = remoteProducts.length > 0
      ? remoteProducts
      : await this.prisma.product.findMany({
          where: {
            OR: [
              ...searchVariants.map((token) => ({ nombre: { contains: token, mode: 'insensitive' as const } })),
              ...searchVariants.map((token) => ({ categoria: { contains: token, mode: 'insensitive' as const } })),
            ],
          },
          select: {
            id: true,
            nombre: true,
            categoria: true,
            precio: true,
            imagen: true,
          },
          take: 24,
          orderBy: { nombre: 'asc' },
        }).then((items) => items.map((item) => ({
          id: item.id,
          nombre: item.nombre,
          descripcion: null,
          codigo: null,
          precio: Number(item.precio),
          stock: null,
          categoria: item.categoria,
          categoriaNombre: item.categoria,
        })));

    const matchingProducts = products
      .map((product) => {
        const haystack = [
          product.nombre,
          product.categoria ?? '',
          product.categoriaNombre ?? '',
          product.codigo ?? '',
          product.descripcion ?? '',
        ].join(' ').toLowerCase();

        const score = searchVariants.reduce((sum, token) => {
          if (product.nombre.toLowerCase().includes(token)) return sum + 5;
          if ((product.categoriaNombre ?? product.categoria ?? '').toLowerCase().includes(token)) return sum + 3;
          if ((product.codigo ?? '').toLowerCase().includes(token)) return sum + 3;
          if (haystack.includes(token)) return sum + 1;
          return sum;
        }, 0);

        return { product, score };
      })
      .filter((item) => item.score > 0)
      .sort((a, b) => b.score - a.score || a.product.nombre.localeCompare(b.product.nombre));

    if (matchingProducts.length === 0) {
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

    const rankedProducts = matchingProducts
      .slice(0, 8)
      .map((item) => item.product);

    const detailedProducts = rankedProducts.slice(0, 5).map((product) => {
      const category = (product.categoriaNombre ?? product.categoria ?? 'Sin categoría').trim();
      const detailLines = [
        `Producto: ${product.nombre}`,
        `Categoria: ${category}`,
        (product.codigo ?? '').trim().length > 0 ? `Codigo: ${product.codigo}` : null,
        user.role === Role.TECNICO ? null : `Precio: ${product.precio.toFixed(2)}`,
        product.stock != null ? `Stock: ${product.stock}` : null,
        (product.descripcion ?? '').trim().length > 0 ? `Descripcion: ${this.buildExcerpt(product.descripcion ?? '')}` : null,
      ].filter((item): item is string => !!item);

      return this.createAppKnowledgeRecord(
        `app-data:product-match:${product.id}`,
        'catalogo',
        'dato-autorizado',
        `Producto encontrado: ${product.nombre}`,
        detailLines.join('\n'),
      );
    });

    result.push(...detailedProducts);

    const lines = rankedProducts.map((p) => {
      const price = user.role === Role.TECNICO ? '' : ` | Precio: ${p.precio.toFixed(2)}`;
      const category = (p.categoriaNombre ?? p.categoria ?? 'Sin categoría').trim();
      const stock = p.stock == null ? '' : ` | Stock: ${p.stock}`;
      const code = (p.codigo ?? '').trim().length === 0 ? '' : ` | Código: ${p.codigo}`;
      return `- ${p.nombre} (${category})${price}${stock}${code}`;
    });

    result.push(
      this.createAppKnowledgeRecord(
        'app-data:catalog-search',
        'catalogo',
        'dato-autorizado',
        `Productos relacionados con "${searchTokens.join(' ')}"`,
        `${lines.join('\n')}\n\nNota: ${rankedProducts.some((product) => product.stock != null) ? 'el stock mostrado proviene del catálogo actual.' : 'esto confirma coincidencias en el catálogo, no inventario físico en tiempo real.'}`,
      ),
    );

    return result;
  }

  private expandSearchTerms(searchTokens: string[]) {
    const variants = new Set<string>();

    for (const token of searchTokens) {
      if (token.trim().length === 0) continue;
      variants.add(token);

      if (token.endsWith('es') && token.length > 4) {
        variants.add(token.slice(0, -2));
      }
      if (token.endsWith('s') && token.length > 3) {
        variants.add(token.slice(0, -1));
      }
      if (!token.endsWith('s')) {
        variants.add(`${token}s`);
      }
    }

    return [...variants].filter((token) => token.trim().length >= 3);
  }

  private extractMeaningfulQueryTerms(
    message: string,
    options?: { extraNoise?: string[]; limit?: number },
  ) {
    const noise = new Set([
      'que',
      'qué',
      'como',
      'cómo',
      'cual',
      'cuál',
      'cuales',
      'cuáles',
      'hay',
      'esta',
      'este',
      'estos',
      'estas',
      'para',
      'con',
      'sin',
      'del',
      'las',
      'los',
      'una',
      'uno',
      'unos',
      'unas',
      'por',
      'favor',
      'sabe',
      'puedes',
      'puede',
      'puedo',
      'necesito',
      'quiero',
      'dime',
      'mira',
      'sobre',
      ...(options?.extraNoise ?? []),
    ].flatMap((term) => this.tokenize(term)));

    const results: string[] = [];
    for (const token of this.tokenize(message)) {
      if (noise.has(token)) continue;
      if (results.includes(token)) continue;
      results.push(token);
      if (results.length >= (options?.limit ?? 6)) break;
    }
    return results;
  }

  private extractNumericQueryTerms(message: string) {
    const matches = message.match(/\d{5,}/g) ?? [];
    return [...new Set(matches.map((item) => item.trim()).filter((item) => item.length >= 5))].slice(0, 3);
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
    const base: KnowledgeRecord[] = [
      this.createAppKnowledgeRecord(
        'app-data:contracts-policy',
        'nomina',
        'politica-app',
        'Acceso a contratos y nómina',
        'Los contratos y la nómina contienen información sensible. Solo se permite acceso según el rol y el alcance del usuario. Por defecto, un usuario solo puede consultar su propio contrato.',
      ),
    ];

    if (!this.canAccessContractData(user.role, dto.context?.route)) {
      return base;
    }

    const contractSelect = {
      id: true,
      nombreCompleto: true,
      email: true,
      telefono: true,
      role: true,
      fechaIngreso: true,
      workContractSignatureUrl: true,
      workContractSignedAt: true,
      workContractVersion: true,
      workContractJobTitle: true,
      workContractStartDate: true,
      workContractWorkSchedule: true,
      workContractWorkLocation: true,
      workContractSalary: true,
      workContractPaymentFrequency: true,
    };

    const targetRecord = await this.prisma.user.findUnique({
      where: { id: user.id },
      select: contractSelect,
    });
    if (!targetRecord) return base;

    base.push(
      this.createAppKnowledgeRecord(
        `app-data:contract:${targetRecord.id}`,
        'nomina',
        'dato-autorizado',
        'Contrato laboral (alcance personal)',
        this.formatContractKnowledge(targetRecord),
      ),
    );

    return base;
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

  private buildRuleOnlyFallback(
    message: string,
    knowledge: KnowledgeRecord[],
    currentUserName?: string | null,
  ): AiAssistantChatResponse {
    const normalizedMessage = message.trim().toLowerCase();
    const hasMeaningfulQuestion = this.tokenize(normalizedMessage).length > 0;
    const matched = hasMeaningfulQuestion ? this.rankRulesForPrompt(message, knowledge).slice(0, 2) : [];
    const visibleKnowledge = knowledge.filter((item) => this.isUserVisibleKnowledge(item));
    const visibleMatched = matched.filter((item) => this.isUserVisibleKnowledge(item));
    const top = visibleMatched[0] ?? visibleKnowledge[0] ?? matched[0] ?? knowledge[0];

    if (!top) {
      return {
        source: 'rules-only',
        content: this.personalizeContent(AiAssistantService.notEnoughDataMessage, currentUserName),
        citations: [],
      };
    }

    const selected = visibleMatched.length ? visibleMatched : [top];
    const citations = this.toUserVisibleCitations(selected);

    const clientMatches = selected.filter((k) => k.id.startsWith('app-data:client-match:'));
    if (clientMatches.length > 0) {
      const intro = clientMatches.length == 1
        ? 'Si, encontre una coincidencia con ese cliente:'
        : `Si, encontre ${clientMatches.length} coincidencias con ese nombre:`;
      const blocks = clientMatches
        .map((k) => k.content.trim())
        .filter((x) => x.length > 0)
        .join('\n\n');

      return {
        source: 'rules-only',
        content: this.personalizeContent(`${intro}\n\n${blocks}`, currentUserName),
        citations: this.toUserVisibleCitations(clientMatches),
        denied: false,
      };
    }

    const productMatches = selected.filter((k) => k.id.startsWith('app-data:product-match:'));
    if (productMatches.length > 0) {
      const intro = productMatches.length == 1
        ? 'Si, encontre este producto relacionado con tu consulta:'
        : `Si, encontre ${productMatches.length} productos relacionados con tu consulta:`;
      const blocks = productMatches
        .map((k) => k.content.trim())
        .filter((x) => x.length > 0)
        .join('\n\n');

      return {
        source: 'rules-only',
        content: this.personalizeContent(`${intro}\n\n${blocks}`, currentUserName),
        citations: this.toUserVisibleCitations(productMatches),
        denied: false,
      };
    }

    const contractMatches = selected.filter(
      (k) => k.id.startsWith('app-data:contract:') || k.id.startsWith('app-data:contract-match:'),
    );
    if (contractMatches.length > 0) {
      const intro = contractMatches.length === 1
        ? 'Si, encontre la informacion del contrato laboral relacionada con tu consulta:'
        : `Si, encontre ${contractMatches.length} contratos laborales relacionados con tu consulta:`;
      const blocks = contractMatches
        .map((k) => k.content.trim())
        .filter((x) => x.length > 0)
        .join('\n\n');

      return {
        source: 'rules-only',
        content: this.personalizeContent(
          `${intro}\n\nResumen del contrato:\n${blocks}\n\nSi necesitas que te explique una clausula, forma de pago, fecha de inicio, puesto o cualquier detalle del contrato, dime exactamente cual parte quieres revisar.`,
          currentUserName,
        ),
        citations: this.toUserVisibleCitations(contractMatches),
        denied: false,
      };
    }

    const isGrowthQuestion = this.hasAnyToken(new Set(this.tokenize(message)), [
      'aprender',
      'aprende',
      'aprendiendo',
      'aprendizaje',
      'crecer',
      'creciendo',
      'actualizar',
      'actualizando',
      'datos',
      'tablas',
      'conocimiento',
      'memoria',
      'sistema',
    ]);
    const growthMatches = selected.filter((k) => k.id.startsWith('app-data:growth-'));
    if (isGrowthQuestion && growthMatches.length > 0) {
      const blocks = growthMatches
        .map((k) => k.content.trim())
        .filter((x) => x.length > 0)
        .join('\n\n');

      return {
        source: 'rules-only',
        content: this.personalizeContent(
          `${blocks}\n\nSi quieres, tambien puedo explicarte por modulo como va creciendo el conocimiento en clientes, productos, contratos, ventas, servicios o normas.`,
          currentUserName,
        ),
        citations: [],
        denied: false,
      };
    }

    const isManualQuestion = this.hasAnyToken(new Set(this.tokenize(message)), [
      'manual',
      'norma',
      'normas',
      'regla',
      'reglas',
      'politica',
      'política',
      'politicas',
      'políticas',
      'protocolo',
      'protocolos',
    ]);
    const manualEntries = knowledge.filter(
      (k) => k.module === 'manual-interno' || k.category === 'politicas',
    );
    const concreteManualEntries = manualEntries.filter((k) => !k.id.startsWith('app-help:'));

    if (isManualQuestion && manualEntries.length > 0) {
      const categoryLabels = Array.from(
        new Set(
          concreteManualEntries
            .map((k) => this.describeManualCategory(k.category))
            .filter((value) => value.length > 0),
        ),
      ).slice(0, 5);
      const generalLines = [
        'Si, tengo conocimiento de las normas y del Manual Interno disponible para tu rol.',
        'En general puedo orientarte sobre politicas, reglas operativas, protocolos, responsabilidades y guias de trabajo por modulo o proceso.',
      ];

      if (concreteManualEntries.length > 0) {
        generalLines.push(`Actualmente tengo acceso a ${concreteManualEntries.length} normas o entradas publicadas relacionadas con el Manual Interno.`);
      }

      if (categoryLabels.length > 0) {
        generalLines.push(`Los temas que cubre con mas frecuencia son: ${categoryLabels.join(', ')}.`);
      }

      const highlightedRules = (matched.length ? matched : concreteManualEntries)
        .filter((k) => !k.id.startsWith('app-help:'))
        .slice(0, 3)
        .map((k) => `- ${k.title}: ${this.buildExcerpt((k.summary ?? '').trim().length ? (k.summary as string) : k.content)}`)
        .join('\n');

      const contentParts = [generalLines.join(' ')];
      if (highlightedRules.length > 0) {
        contentParts.push(`Detalle general relacionado con tu consulta:\n${highlightedRules}`);
      }
      contentParts.push('Si tienes una pregunta mas especifica, dime la norma, politica, regla o area que quieres revisar y te la explico con mas detalle.');

      return {
        source: 'rules-only',
        content: this.personalizeContent(contentParts.join('\n\n'), currentUserName),
        citations: this.toUserVisibleCitations((visibleMatched.length ? visibleMatched : manualEntries).slice(0, 3)),
        denied: false,
      };
    }

    const parts = selected
      .map((k, index) => {
        const excerpt = this.buildExcerpt((k.summary ?? '').trim().length ? (k.summary as string) : k.content);
        const prefix = index === 0 ? `Según "${k.title}"` : `También aplica "${k.title}"`;
        return excerpt.length ? `${prefix}: ${excerpt}` : prefix;
      })
      .filter((x) => x.trim().length > 0);

    return {
      source: 'rules-only',
      content: this.personalizeContent(
        parts.length ? parts.join(' ') : AiAssistantService.notEnoughDataMessage,
        currentUserName,
      ),
      citations: this.toUserVisibleCitations(selected),
      denied: false,
    };
  }

  private personalizeContent(content: string, currentUserName?: string | null) {
    const trimmed = content.trim();
    if (!trimmed || !currentUserName || currentUserName.trim().length === 0) {
      return trimmed;
    }

    const safeName = currentUserName.trim();
    const lower = trimmed.toLowerCase();
    if (lower.startsWith(`${safeName.toLowerCase()},`) || lower.startsWith(`hola ${safeName.toLowerCase()}`)) {
      return trimmed;
    }

    if (trimmed === AiAssistantService.notEnoughDataMessage) {
      return `${safeName}, ${trimmed.charAt(0).toLowerCase()}${trimmed.slice(1)}`;
    }

    const intro = this.buildPersonalizedIntro(safeName, lower);
    return `${intro}\n\n${trimmed}`;
  }

  private buildPersonalizedIntro(currentUserName: string, normalizedContent: string) {
    if (
      normalizedContent.includes('contrato laboral') ||
      normalizedContent.includes('resumen del contrato') ||
      normalizedContent.includes('salario:') ||
      normalizedContent.includes('frecuencia de pago')
    ) {
      return `${currentUserName}, aqui tienes el resumen de contrato que encontre para ti.`;
    }

    if (
      normalizedContent.includes('manual interno') ||
      normalizedContent.includes('norma') ||
      normalizedContent.includes('politica') ||
      normalizedContent.includes('regla') ||
      normalizedContent.includes('protocolo')
    ) {
      return `${currentUserName}, te comparto un resumen claro de las normas y lineamientos disponibles.`;
    }

    if (
      normalizedContent.includes('coincidencia con ese cliente') ||
      normalizedContent.includes('cliente:') ||
      normalizedContent.includes('movimientos del cliente')
    ) {
      return `${currentUserName}, esto es lo que encontre sobre el cliente consultado.`;
    }

    if (
      normalizedContent.includes('producto:') ||
      normalizedContent.includes('precio:') ||
      normalizedContent.includes('stock:') ||
      normalizedContent.includes('productos relacionados con tu consulta')
    ) {
      return `${currentUserName}, esto es lo que encontre del producto que consultaste.`;
    }

    return `${currentUserName}, aqui tienes la informacion que encontre.`;
  }

  private async getCurrentUserPreferredName(userId: string) {
    const record = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { nombreCompleto: true },
    });

    const raw = (record?.nombreCompleto ?? '').trim();
    if (!raw) return null;

    const [firstName] = raw.split(/\s+/).filter((part) => part.trim().length > 0);
    return firstName?.trim() || raw;
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

  private formatContractKnowledge(record: {
    id: string;
    nombreCompleto: string;
    email: string;
    telefono: string;
    role: Role;
    fechaIngreso: Date | null;
    workContractSignatureUrl: string | null;
    workContractSignedAt: Date | null;
    workContractVersion: string | null;
    workContractJobTitle: string | null;
    workContractStartDate: Date | null;
    workContractWorkSchedule: string | null;
    workContractWorkLocation: string | null;
    workContractSalary: string | null;
    workContractPaymentFrequency: string | null;
    workContractPaymentMethod: string | null;
    workContractClauseOverrides: Prisma.JsonValue | null;
    workContractCustomClauses: string | null;
  }) {
    const clauseSummary = this.summarizeContractClauses(record.workContractClauseOverrides, record.workContractCustomClauses);
    const lines = [
      `Empleado: ${record.nombreCompleto}`,
      `Rol: ${record.role}`,
      `Correo: ${record.email}`,
      `Telefono: ${record.telefono}`,
      `Puesto: ${record.workContractJobTitle ?? 'N/D'}`,
      `Inicio de contrato: ${record.workContractStartDate ? record.workContractStartDate.toISOString().slice(0, 10) : 'N/D'}`,
      `Fecha de ingreso: ${record.fechaIngreso ? record.fechaIngreso.toISOString().slice(0, 10) : 'N/D'}`,
      `Horario laboral: ${record.workContractWorkSchedule ?? 'N/D'}`,
      `Lugar de trabajo: ${record.workContractWorkLocation ?? 'N/D'}`,
      `Salario: ${record.workContractSalary ?? 'N/D'}`,
      `Frecuencia de pago: ${record.workContractPaymentFrequency ?? 'N/D'}`,
      `Metodo de pago: ${record.workContractPaymentMethod ?? 'N/D'}`,
      `Version del contrato: ${record.workContractVersion ?? 'N/D'}`,
      `Estado de firma: ${record.workContractSignedAt ? `Firmado el ${record.workContractSignedAt.toISOString()}` : 'Pendiente o no registrado'}`,
      record.workContractSignatureUrl ? 'Firma digital o archivo del contrato: disponible' : 'Firma digital o archivo del contrato: no registrado',
      clauseSummary,
    ].filter((item) => item.trim().length > 0);

    return lines.join('\n');
  }

  private summarizeContractClauses(
    overrides: Prisma.JsonValue | null,
    customClauses: string | null,
  ) {
    const parts: string[] = [];

    if (customClauses && customClauses.trim().length > 0) {
      parts.push(`Clausulas personalizadas: ${this.buildExcerpt(customClauses)}`);
    }

    if (overrides && typeof overrides === 'object') {
      const overrideCount = Array.isArray(overrides) ? overrides.length : Object.keys(overrides as Record<string, unknown>).length;
      if (overrideCount > 0) {
        parts.push(`Ajustes o clausulas sobrescritas: ${overrideCount} registradas.`);
      }
    }

    if (parts.length === 0) {
      return 'Clausulas adicionales: no registradas.';
    }

    return parts.join(' ');
  }

  private describeManualCategory(category: string) {
    switch ((category ?? '').trim().toLowerCase()) {
      case 'politicas':
        return 'politicas internas';
      case 'precios':
        return 'reglas de precios';
      case 'garantias':
        return 'politicas de garantia';
      case 'servicios':
        return 'protocolos de servicio';
      case 'productos':
        return 'lineamientos de productos y servicios';
      case 'modulo':
        return 'guias por modulo';
      case 'general':
        return 'reglas generales y responsabilidades';
      default:
        return category.trim();
    }
  }

  private isUserVisibleKnowledge(record: KnowledgeRecord) {
    if (record.category === 'memoria') return false;
    if (record.id === 'app-data:conversation-context') return false;
    if (record.id.startsWith('app-memory:')) return false;
    return true;
  }

  private toUserVisibleCitations(records: KnowledgeRecord[]) {
    return records
      .filter((record) => this.isUserVisibleKnowledge(record))
      .map((record) => this.toCitation(record));
  }

  private formatKnowledgeDate(value: Date | null) {
    if (!value) return 'sin fecha';
    return value.toISOString().slice(0, 19).replace('T', ' ');
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
