import { BadRequestException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Role } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { UpdateSettingsDto } from './dto/update-settings.dto';

type Actor = { role?: Role | string };

type ProductsSource = 'FULLPOS' | 'FULLPOS_DIRECT' | 'LOCAL';
type AppConfigResponseShape = {
  companyName?: string | null;
  rnc?: string | null;
  phone?: string | null;
  address?: string | null;
  legalRepresentativeName?: string | null;
  legalRepresentativeCedula?: string | null;
  legalRepresentativeRole?: string | null;
  legalRepresentativeNationality?: string | null;
  legalRepresentativeCivilStatus?: string | null;
  logoBase64?: string | null;
  openAiApiKey?: string | null;
  openAiModel?: string | null;
  evolutionApiBaseUrl?: string | null;
  evolutionApiInstanceName?: string | null;
  evolutionApiApiKey?: string | null;
  operationsTechCanViewAllServices?: boolean | null;
  updatedAt?: Date | null;
};

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

  private sanitizeLogoBase64(value?: string | null) {
    const cleaned = this.sanitizeNullable(value);
    if (cleaned == null) return null;

    const normalized = cleaned
      .replace(/^data:image\/[a-zA-Z0-9.+-]+;base64,/, '')
      .replace(/\s+/g, '');

    let bytes: Buffer;
    try {
      bytes = Buffer.from(normalized, 'base64');
    } catch {
      throw new BadRequestException('El logo enviado no tiene un formato base64 valido.');
    }

    if (bytes.length === 0) {
      throw new BadRequestException('El logo enviado esta vacio o no es una imagen valida.');
    }

    const comparableInput = normalized.replace(/=+$/, '');
    const comparableOutput = bytes.toString('base64').replace(/=+$/, '');
    if (comparableInput !== comparableOutput) {
      throw new BadRequestException('El logo enviado no tiene un formato base64 valido.');
    }

    const maxLogoBytes = 5 * 1024 * 1024;
    if (bytes.length > maxLogoBytes) {
      throw new BadRequestException('El logo excede el tamano maximo permitido de 5 MB.');
    }

    return normalized;
  }

  private toResponse(config: AppConfigResponseShape, actor?: Actor) {
    const isAdmin = `${actor?.role ?? ''}`.toUpperCase() === 'ADMIN';
    const productsSource = this.resolveProductsSource();

    return {
      companyName: config.companyName,
      rnc: config.rnc,
      phone: config.phone,
      address: config.address,
      legalRepresentativeName: config.legalRepresentativeName,
      legalRepresentativeCedula: config.legalRepresentativeCedula,
      legalRepresentativeRole: config.legalRepresentativeRole,
      legalRepresentativeNationality: config.legalRepresentativeNationality,
      legalRepresentativeCivilStatus: config.legalRepresentativeCivilStatus,
      logoBase64: config.logoBase64,
      openAiModel: config.openAiModel,
      hasOpenAiApiKey: !!config.openAiApiKey,
      openAiApiKey: isAdmin ? config.openAiApiKey : null,
      evolutionApiBaseUrl: config.evolutionApiBaseUrl,
      evolutionApiInstanceName: config.evolutionApiInstanceName,
      hasEvolutionApiApiKey: !!config.evolutionApiApiKey,
      evolutionApiApiKey: isAdmin ? config.evolutionApiApiKey : null,
      operationsTechCanViewAllServices: !!config.operationsTechCanViewAllServices,
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
          legalRepresentativeName: '',
          legalRepresentativeCedula: '',
          legalRepresentativeRole: '',
          legalRepresentativeNationality: '',
          legalRepresentativeCivilStatus: '',
          logoBase64: null,
          openAiModel: 'gpt-4o-mini',
          hasOpenAiApiKey: false,
          openAiApiKey: null,
          evolutionApiBaseUrl: '',
          evolutionApiInstanceName: '',
          hasEvolutionApiApiKey: false,
          evolutionApiApiKey: null,
          operationsTechCanViewAllServices: false,
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
          ...(dto.legalRepresentativeName != null
              ? {
                  legalRepresentativeName: this.sanitizeText(
                    dto.legalRepresentativeName,
                  ),
                }
              : {}),
          ...(dto.legalRepresentativeCedula != null
              ? {
                  legalRepresentativeCedula: this.sanitizeText(
                    dto.legalRepresentativeCedula,
                  ),
                }
              : {}),
          ...(dto.legalRepresentativeRole != null
              ? {
                  legalRepresentativeRole: this.sanitizeText(
                    dto.legalRepresentativeRole,
                  ),
                }
              : {}),
          ...(dto.legalRepresentativeNationality != null
              ? {
                  legalRepresentativeNationality: this.sanitizeText(
                    dto.legalRepresentativeNationality,
                  ),
                }
              : {}),
          ...(dto.legalRepresentativeCivilStatus != null
              ? {
                  legalRepresentativeCivilStatus: this.sanitizeText(
                    dto.legalRepresentativeCivilStatus,
                  ),
                }
              : {}),
          ...(dto.logoBase64 != null
              ? { logoBase64: this.sanitizeLogoBase64(dto.logoBase64) }
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
            ...(dto.operationsTechCanViewAllServices != null
              ? { operationsTechCanViewAllServices: !!dto.operationsTechCanViewAllServices }
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
