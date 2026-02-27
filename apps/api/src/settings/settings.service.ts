import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Role } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { UpdateSettingsDto } from './dto/update-settings.dto';

type Actor = { role?: Role | string };

type ProductsSource = 'FULLPOS' | 'LOCAL';

@Injectable()
export class SettingsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  private resolveProductsSource(): ProductsSource {
    const rawSource = (this.config.get<string>('PRODUCTS_SOURCE') ?? '').trim().toUpperCase();
    const nodeEnv = (this.config.get<string>('NODE_ENV') ?? process.env.NODE_ENV ?? 'development').toLowerCase();
    const defaultSource: ProductsSource = nodeEnv === 'production' ? 'LOCAL' : 'FULLPOS';
    return rawSource === 'LOCAL' || rawSource === 'FULLPOS' ? (rawSource as ProductsSource) : defaultSource;
  }

  private async ensureConfig() {
    return this.prisma.appConfig.upsert({
      where: { id: 'global' },
      create: { id: 'global' },
      update: {},
    });
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
      productsSource,
      productsReadOnly: productsSource === 'FULLPOS',
      updatedAt: config.updatedAt,
    };
  }

  async getSettings(actor?: Actor) {
    const config = await this.ensureConfig();
    return this.toResponse(config, actor);
  }

  async updateSettings(dto: UpdateSettingsDto, actor?: Actor) {
    await this.ensureConfig();

    const updated = await this.prisma.appConfig.update({
      where: { id: 'global' },
      data: {
        ...(dto.companyName != null ? { companyName: this.sanitizeText(dto.companyName) } : {}),
        ...(dto.rnc != null ? { rnc: this.sanitizeText(dto.rnc) } : {}),
        ...(dto.phone != null ? { phone: this.sanitizeText(dto.phone) } : {}),
        ...(dto.address != null ? { address: this.sanitizeText(dto.address) } : {}),
        ...(dto.logoBase64 != null ? { logoBase64: this.sanitizeNullable(dto.logoBase64) } : {}),
        ...(dto.openAiApiKey != null
          ? { openAiApiKey: this.sanitizeNullable(dto.openAiApiKey) }
          : {}),
        ...(dto.openAiModel != null
          ? {
              openAiModel:
                this.sanitizeText(dto.openAiModel).length === 0
                  ? 'gpt-4o-mini'
                  : this.sanitizeText(dto.openAiModel),
            }
          : {}),
      },
    });

    return this.toResponse(updated, actor);
  }
}
