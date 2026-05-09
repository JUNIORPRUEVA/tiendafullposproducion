import { Module } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CrmCommercialController } from './crm-commercial.controller';
import { CrmCommercialService } from './crm-commercial.service';

@Module({
  controllers: [CrmCommercialController],
  providers: [CrmCommercialService, PrismaService],
})
export class CrmCommercialModule {}
