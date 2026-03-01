import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { ReportLocationDto } from './dto/report-location.dto';

@Injectable()
export class LocationsService {
  constructor(private readonly prisma: PrismaService) {}

  async reportLocation(userId: string | undefined, dto: ReportLocationDto) {
    if (!userId) throw new UnauthorizedException('Usuario no autenticado');

    const prismaAny = this.prisma as any;

    const recordedAt = dto.recordedAt ? new Date(dto.recordedAt) : undefined;

    return prismaAny.userLocation.upsert({
      where: { userId },
      create: {
        userId,
        latitude: dto.latitude,
        longitude: dto.longitude,
        accuracyMeters: dto.accuracyMeters,
        altitudeMeters: dto.altitudeMeters,
        headingDegrees: dto.headingDegrees,
        speedMps: dto.speedMps,
        recordedAt,
      },
      update: {
        latitude: dto.latitude,
        longitude: dto.longitude,
        accuracyMeters: dto.accuracyMeters,
        altitudeMeters: dto.altitudeMeters,
        headingDegrees: dto.headingDegrees,
        speedMps: dto.speedMps,
        recordedAt,
      },
      select: {
        userId: true,
        latitude: true,
        longitude: true,
        accuracyMeters: true,
        altitudeMeters: true,
        headingDegrees: true,
        speedMps: true,
        recordedAt: true,
        updatedAt: true,
      },
    });
  }

  async listLatestLocationsForAdmin() {
    const prismaAny = this.prisma as any;
    return prismaAny.userLocation.findMany({
      orderBy: { updatedAt: 'desc' },
      select: {
        userId: true,
        latitude: true,
        longitude: true,
        accuracyMeters: true,
        altitudeMeters: true,
        headingDegrees: true,
        speedMps: true,
        recordedAt: true,
        updatedAt: true,
        user: {
          select: {
            id: true,
            nombreCompleto: true,
            email: true,
            role: true,
            blocked: true,
          },
        },
      },
    });
  }
}
