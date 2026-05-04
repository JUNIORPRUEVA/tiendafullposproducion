import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { UpdateMarketingConfigDto } from './dto/update-marketing-config.dto';

@Injectable()
export class MarketingConfigService {
  constructor(private readonly prisma: PrismaService) {}

  private readonly defaults = {
    active: false,
    paused: false,
    dailyStoriesCount: 3,
    generationTime: '08:00',
    autoRegenerate: false,
    regenerateAfterHours: 6,
    targetCity: '',
    brandTone: '',
    priorityProducts: [] as string[],
  };

  async getOrCreate(companyId: string) {
    const existing = await this.prisma.marketingFlowConfig.findUnique({
      where: { companyId },
    });
    if (existing) return existing;

    return this.prisma.marketingFlowConfig.create({
      data: {
        companyId,
        ...this.defaults,
      },
    });
  }

  async update(companyId: string, dto: UpdateMarketingConfigDto, userId: string) {
    const config = await this.getOrCreate(companyId);
    return this.prisma.marketingFlowConfig.update({
      where: { id: config.id },
      data: {
        ...(dto.flujo_activo != null ? { active: dto.flujo_activo } : {}),
        ...(dto.pausado != null ? { paused: dto.pausado } : {}),
        ...(dto.cantidad_estados_diarios != null
          ? { dailyStoriesCount: dto.cantidad_estados_diarios }
          : {}),
        ...(dto.hora_generacion != null
          ? { generationTime: dto.hora_generacion.trim() }
          : {}),
        ...(dto.auto_regenerar_si_no_aprueba != null
          ? { autoRegenerate: dto.auto_regenerar_si_no_aprueba }
          : {}),
        ...(dto.horas_para_regenerar != null
          ? { regenerateAfterHours: dto.horas_para_regenerar }
          : {}),
        ...(dto.ciudad_objetivo != null ? { targetCity: dto.ciudad_objetivo.trim() } : {}),
        ...(dto.tono_de_marca != null ? { brandTone: dto.tono_de_marca.trim() } : {}),
        ...(dto.productos_prioritarios != null
          ? {
              priorityProducts: dto.productos_prioritarios
                .map((item) => item.trim())
                .filter((item) => item.length > 0),
            }
          : {}),
        updatedByUserId: userId,
      },
    });
  }

  async activateFlow(companyId: string, userId: string) {
    const config = await this.getOrCreate(companyId);
    return this.prisma.marketingFlowConfig.update({
      where: { id: config.id },
      data: {
        active: true,
        paused: false,
        updatedByUserId: userId,
      },
    });
  }

  async pauseFlow(companyId: string, userId: string) {
    const config = await this.getOrCreate(companyId);
    return this.prisma.marketingFlowConfig.update({
      where: { id: config.id },
      data: {
        paused: true,
        updatedByUserId: userId,
      },
    });
  }

  async resetFlow(companyId: string, userId: string) {
    const config = await this.getOrCreate(companyId);

    await this.prisma.$transaction([
      this.prisma.marketingDailyStory.deleteMany({ where: { companyId } }),
      this.prisma.marketingFlowConfig.update({
        where: { id: config.id },
        data: {
          ...this.defaults,
          updatedByUserId: userId,
        },
      }),
    ]);

    return this.getOrCreate(companyId);
  }
}
