import { Injectable } from '@nestjs/common';
import { Prisma, PunchType, Role, ServiceStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

type Severity = 'high' | 'medium' | 'info';

type PanelAlert = {
  code: string;
  title: string;
  detail: string;
  severity: Severity;
};

type AiConfig = {
  apiKey?: string;
  model?: string;
};

@Injectable()
export class AdminPanelService {
  constructor(private readonly prisma: PrismaService) {}

  parseDays(raw?: string) {
    const value = Number.parseInt((raw ?? '').trim(), 10);
    if (!Number.isFinite(value)) return 7;
    return Math.max(1, Math.min(30, value));
  }

  private startOfDay(date: Date) {
    const value = new Date(date);
    value.setHours(0, 0, 0, 0);
    return value;
  }

  private dateOnly(date: Date) {
    const month = `${date.getMonth() + 1}`.padStart(2, '0');
    const day = `${date.getDate()}`.padStart(2, '0');
    return `${date.getFullYear()}-${month}-${day}`;
  }

  private buildRuleBasedNarrative(metrics: Record<string, unknown>, alerts: PanelAlert[]) {
    const lines: string[] = [];
    lines.push('Resumen automático de administración:');
    lines.push(`- Usuarios activos: ${metrics.activeUsers ?? 0}`);
    lines.push(`- Sin ponchar hoy: ${metrics.missingPunchToday ?? 0}`);
    lines.push(`- Sin ventas en ventana: ${metrics.noSalesInWindow ?? 0}`);
    lines.push(`- Tardanzas hoy: ${metrics.lateArrivalsToday ?? 0}`);

    if (alerts.length === 0) {
      lines.push('No se detectaron novedades críticas en este momento.');
      return lines.join('\n');
    }

    lines.push('Novedades detectadas:');
    for (const alert of alerts.slice(0, 8)) {
      lines.push(`- [${alert.severity.toUpperCase()}] ${alert.title}: ${alert.detail}`);
    }
    return lines.join('\n');
  }

  async getOverview(days = 7) {
    const now = new Date();
    const todayStart = this.startOfDay(now);
    const windowStart = new Date(todayStart);
    windowStart.setDate(windowStart.getDate() - (days - 1));

    const users = await this.prisma.user.findMany({
      select: {
        id: true,
        nombreCompleto: true,
        role: true,
        blocked: true,
      },
      orderBy: { nombreCompleto: 'asc' },
    });

    const activeUsers = users.filter((user) => !user.blocked);

    const punchesToday = await this.prisma.punch.findMany({
      where: { timestamp: { gte: todayStart } },
      select: {
        userId: true,
        type: true,
        timestamp: true,
      },
      orderBy: [{ timestamp: 'asc' }],
    });

    const salesWindow = await this.prisma.sale.findMany({
      where: {
        isDeleted: false,
        saleDate: { gte: windowStart },
      },
      select: {
        userId: true,
        totalSold: true,
        saleDate: true,
      },
    });

    const openOperations = await this.prisma.service.count({
      where: {
        status: {
          in: [
            ServiceStatus.RESERVED,
            ServiceStatus.SURVEY,
            ServiceStatus.SCHEDULED,
            ServiceStatus.IN_PROGRESS,
            ServiceStatus.WARRANTY,
          ],
        },
      },
    });

    const byUserPunchCount = new Map<string, number>();
    const firstEntradaByUser = new Map<string, Date>();

    for (const punch of punchesToday) {
      byUserPunchCount.set(
        punch.userId,
        (byUserPunchCount.get(punch.userId) ?? 0) + 1,
      );
      if (punch.type === PunchType.ENTRADA_LABOR && !firstEntradaByUser.has(punch.userId)) {
        firstEntradaByUser.set(punch.userId, new Date(punch.timestamp));
      }
    }

    const sellers = activeUsers.filter(
      (user) => user.role === Role.VENDEDOR || user.role === Role.ASISTENTE,
    );

    const byUserSalesCount = new Map<string, number>();
    for (const sale of salesWindow) {
      byUserSalesCount.set(sale.userId, (byUserSalesCount.get(sale.userId) ?? 0) + 1);
    }

    const noPunchUsers = activeUsers
      .filter((user) => user.role !== Role.ADMIN)
      .filter((user) => !byUserPunchCount.has(user.id));

    const noSalesUsers = sellers.filter((user) => !byUserSalesCount.has(user.id));

    const lateUsers = activeUsers.filter((user) => {
      const firstEntrada = firstEntradaByUser.get(user.id);
      if (!firstEntrada) return false;
      const hours = firstEntrada.getHours();
      const minutes = firstEntrada.getMinutes();
      return hours > 9 || (hours === 9 && minutes > 10);
    });

    const alerts: PanelAlert[] = [];

    for (const user of noPunchUsers.slice(0, 12)) {
      alerts.push({
        code: 'MISSING_PUNCH',
        title: 'Empleado sin ponche hoy',
        detail: `${user.nombreCompleto} no tiene registros de ponche en ${this.dateOnly(now)}.`,
        severity: 'high',
      });
    }

    for (const user of noSalesUsers.slice(0, 12)) {
      alerts.push({
        code: 'NO_SALES_WINDOW',
        title: 'Empleado sin ventas en ventana',
        detail: `${user.nombreCompleto} no registra ventas en los últimos ${days} días.`,
        severity: 'medium',
      });
    }

    for (const user of lateUsers.slice(0, 12)) {
      const firstEntrada = firstEntradaByUser.get(user.id);
      alerts.push({
        code: 'LATE_ARRIVAL',
        title: 'Llegada tardía detectada',
        detail: `${user.nombreCompleto} marcó entrada a las ${firstEntrada?.toLocaleTimeString('es-DO', { hour: '2-digit', minute: '2-digit' }) ?? '--:--'}.`,
        severity: 'medium',
      });
    }

    return {
      generatedAt: now.toISOString(),
      windowDays: days,
      metrics: {
        totalUsers: users.length,
        activeUsers: activeUsers.length,
        blockedUsers: users.filter((u) => u.blocked).length,
        punchesToday: punchesToday.length,
        missingPunchToday: noPunchUsers.length,
        salesInWindow: salesWindow.length,
        noSalesInWindow: noSalesUsers.length,
        lateArrivalsToday: lateUsers.length,
        openOperations,
      },
      alerts,
    };
  }

  async getAiInsights(days = 7, config?: AiConfig) {
    const overview = await this.getOverview(days);
    const metrics = overview.metrics as Record<string, unknown>;
    const alerts = overview.alerts as PanelAlert[];
    const ruleNarrative = this.buildRuleBasedNarrative(metrics, alerts);

    const appConfigRows = await this.prisma.$queryRaw<
      Array<{ openAiApiKey: string | null; openAiModel: string | null }>
    >(
      Prisma.sql`SELECT "openAiApiKey", "openAiModel" FROM "app_config" WHERE id = 'global' LIMIT 1`,
    );
    const appConfig = appConfigRows[0];

    const apiKey = (
      config?.apiKey ??
      process.env.OPENAI_API_KEY ??
      appConfig?.openAiApiKey ??
      ''
    ).trim();
    const preferredModel = (
      config?.model ??
      process.env.OPENAI_MODEL ??
      appConfig?.openAiModel ??
      ''
    ).trim();

    const autoCandidatesEnv = (process.env.OPENAI_MODEL_CANDIDATES ?? '').trim();
    const autoCandidates = autoCandidatesEnv.length > 0
      ? autoCandidatesEnv
          .split(',')
          .map((item) => item.trim())
          .filter((item) => item.length > 0)
      : ['gpt-5', 'gpt-4.1', 'gpt-4o', 'gpt-4o-mini'];

    const modelCandidates = [preferredModel, ...autoCandidates].filter(
      (value, index, list) => value.length > 0 && list.indexOf(value) === index,
    );

    if (!apiKey) {
      return {
        source: 'rules',
        message: `${ruleNarrative}\n\nConfigura la API key en Ajustes > Configuración de API o define OPENAI_API_KEY en el backend para análisis IA avanzado.`,
        metrics,
        alerts,
      };
    }

    try {
      for (const model of modelCandidates) {
        const response = await fetch('https://api.openai.com/v1/chat/completions', {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${apiKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            model,
            temperature: 0.2,
            messages: [
              {
                role: 'system',
                content:
                  'Eres un asistente de administración de empresa. Analiza métricas y alertas y responde en español con prioridades, riesgos y acciones concretas para hoy.',
              },
              {
                role: 'user',
                content: JSON.stringify({
                  generatedAt: overview.generatedAt,
                  windowDays: overview.windowDays,
                  metrics,
                  alerts,
                }),
              },
            ],
          }),
        });

        if (!response.ok) {
          continue;
        }

        const payload = (await response.json()) as {
          choices?: Array<{ message?: { content?: string } }>;
        };

        const message =
          payload.choices?.[0]?.message?.content?.trim() ||
          `${ruleNarrative}\n\nNo se recibió contenido de OpenAI.`;

        return {
          source: 'openai',
          selectedModel: model,
          message,
          metrics,
          alerts,
        };
      }

      throw new Error('OpenAI no devolvió respuesta válida con los modelos candidatos');
    } catch {
      return {
        source: 'rules',
        message: `${ruleNarrative}\n\nFallo temporal de OpenAI o modelo no disponible, usando motor de reglas interno.`,
        metrics,
        alerts,
      };
    }
  }
}
