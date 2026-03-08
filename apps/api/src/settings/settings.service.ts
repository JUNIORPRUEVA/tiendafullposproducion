import { BadRequestException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Role } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { UpdateSettingsDto } from './dto/update-settings.dto';

type Actor = { role?: Role | string };

type ProductsSource = 'FULLPOS' | 'FULLPOS_DIRECT' | 'LOCAL';

@Injectable()
export class SettingsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  private resolveProductsSource(): ProductsSource {
    const rawSource = (this.config.get<string>('PRODUCTS_SOURCE') ?? '').trim().toUpperCase();
    const nodeEnv = (this.config.get<string>('NODE_ENV') ?? process.env.NODE_ENV ?? 'development').toLowerCase();
    const hasDirectDb =
      ((this.config.get<string>('FULLPOS_DIRECT_DATABASE_URL') ?? this.config.get<string>('FULLPOS_DB_URL') ?? '').trim().length > 0) &&
      ((this.config.get<string>('FULLPOS_DIRECT_COMPANY_ID') ?? this.config.get<string>('FULLPOS_COMPANY_ID') ?? '').trim().length > 0);
    const defaultSource: ProductsSource = hasDirectDb
      ? 'FULLPOS_DIRECT'
      : (nodeEnv === 'production' ? 'LOCAL' : 'FULLPOS');
    return rawSource === 'LOCAL' || rawSource === 'FULLPOS' || rawSource === 'FULLPOS_DIRECT'
      ? (rawSource as ProductsSource)
      : defaultSource;
  }

  private async ensureConfig() {
    try {
      return await this.prisma.appConfig.upsert({
        where: { id: 'global' },
        create: { id: 'global' },
        update: {},
      });
    } catch (e) {
      if (this.isMissingAppConfigTableOrColumns(e)) {
        throw new BadRequestException(
          'Configuración no disponible: faltan migraciones en la base de datos (tabla/columnas de app_config). Ejecuta: prisma migrate deploy.',
        );
      }
      throw e;
    }
  }

  private isMissingAppConfigTableOrColumns(error: unknown) {
    const anyErr = error as any;
    const code = (anyErr?.code ?? anyErr?.meta?.code ?? '').toString();
    const message = (anyErr?.message ?? '').toString();

    // Postgres codes:
    // 42P01 = undefined_table
    // 42703 = undefined_column
    const pgTableMissing = code === '42P01' || message.includes('42P01');
    const pgColumnMissing = code === '42703' || message.includes('42703');

    // Prisma codes:
    // P2021 = table does not exist
    // P2022 = column does not exist
    const prismaTableMissing = code === 'P2021' || message.includes('P2021');
    const prismaColumnMissing = code === 'P2022' || message.includes('P2022');

    const mentionsAppConfig =
      message.toLowerCase().includes('app_config') ||
      message.toLowerCase().includes('appconfig');

    return (
      pgTableMissing ||
      pgColumnMissing ||
      prismaTableMissing ||
      prismaColumnMissing ||
      (mentionsAppConfig && (message.toLowerCase().includes('does not exist') || message.toLowerCase().includes('no such table')))
    );
  }

  private sanitizeText(value?: string | null) {
    return (value ?? '').trim();
  }

  private sanitizeNullable(value?: string | null) {
    const cleaned = this.sanitizeText(value);
    return cleaned.length === 0 ? null : cleaned;
  }

  private toResponse(config: Awaited<ReturnType<SettingsService['ensureConfig']>>, actor?: Actor) {
    const isAdmin = `${actor?.role ?? ''}`.toUpperCase() === 'ADMIN';
    const productsSource = this.resolveProductsSource();

    return {
      companyName: config.companyName,
      rnc: config.rnc,
      phone: config.phone,
      address: config.address,
      logoBase64: config.logoBase64,
      openAiModel: config.openAiModel,
      hasOpenAiApiKey: !!config.openAiApiKey,
      openAiApiKey: isAdmin ? config.openAiApiKey : null,
      evolutionApiBaseUrl: config.evolutionApiBaseUrl,
      evolutionApiInstanceName: config.evolutionApiInstanceName,
      hasEvolutionApiApiKey: !!config.evolutionApiApiKey,
      evolutionApiApiKey: isAdmin ? config.evolutionApiApiKey : null,
      productsSource,
      productsReadOnly: productsSource === 'FULLPOS' || productsSource === 'FULLPOS_DIRECT',
      updatedAt: config.updatedAt,
    };
  }

  async getSettings(actor?: Actor) {
    try {
      const config = await this.ensureConfig();
      return this.toResponse(config, actor);
    } catch (e) {
      if (this.isMissingAppConfigTableOrColumns(e)) {
        // Permite que la UI cargue sin romper por completo.
        return {
          companyName: '',
          rnc: '',
          phone: '',
          address: '',
          logoBase64: null,
          openAiModel: 'gpt-4o-mini',
          hasOpenAiApiKey: false,
          openAiApiKey: null,
          evolutionApiBaseUrl: '',
          evolutionApiInstanceName: '',
          hasEvolutionApiApiKey: false,
          evolutionApiApiKey: null,
          productsSource: this.resolveProductsSource(),
          productsReadOnly: this.resolveProductsSource() === 'FULLPOS' || this.resolveProductsSource() === 'FULLPOS_DIRECT',
          updatedAt: null,
          migrationRequired: true,
        } as any;
      }
      throw e;
    }
  }

  async updateSettings(dto: UpdateSettingsDto, actor?: Actor) {
    await this.ensureConfig();

    let updated;
    try {
      updated = await this.prisma.appConfig.update({
        where: { id: 'global' },
        data: {
          ...(dto.companyName != null
              ? { companyName: this.sanitizeText(dto.companyName) }
              : {}),
          ...(dto.rnc != null ? { rnc: this.sanitizeText(dto.rnc) } : {}),
          ...(dto.phone != null ? { phone: this.sanitizeText(dto.phone) } : {}),
          ...(dto.address != null
              ? { address: this.sanitizeText(dto.address) }
              : {}),
          ...(dto.logoBase64 != null
              ? { logoBase64: this.sanitizeNullable(dto.logoBase64) }
              : {}),
          ...(dto.openAiApiKey != null
              ? { openAiApiKey: this.sanitizeNullable(dto.openAiApiKey) }
              : {}),
          ...(dto.openAiModel != null
              ? {
                  openAiModel: (() => {
                    const cleaned = this.sanitizeText(dto.openAiModel);
                    return cleaned.length === 0 ? 'gpt-4o-mini' : cleaned;
                  })(),
                }
              : {}),
          ...(dto.evolutionApiBaseUrl != null
              ? { evolutionApiBaseUrl: this.sanitizeText(dto.evolutionApiBaseUrl) }
              : {}),
          ...(dto.evolutionApiInstanceName != null
              ? {
                  evolutionApiInstanceName: this.sanitizeText(
                    dto.evolutionApiInstanceName,
                  ),
                }
              : {}),
          ...(dto.evolutionApiApiKey != null
              ? { evolutionApiApiKey: this.sanitizeNullable(dto.evolutionApiApiKey) }
              : {}),
        },
      });
    } catch (e) {
      if (this.isMissingAppConfigTableOrColumns(e)) {
        throw new BadRequestException(
          'No se pudo guardar la configuración porque faltan migraciones en la base de datos. Ejecuta: prisma migrate deploy (migración app_config).',
        );
      }
      throw e;
    }

    return this.toResponse(updated, actor);
  }
}
