import { Controller, Get } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Controller()
export class HealthController {
  constructor(private readonly prisma: PrismaService) {}

  @Get()
  getRootHealth() {
    return { status: 'ok' };
  }

  @Get('health')
  getHealth() {
    return { status: 'ok' };
  }

  @Get('health/db')
  async getDbHealth() {
    await this.prisma.$queryRaw`SELECT 1`;
    return { status: 'ok', db: 'ok' };
  }
}
