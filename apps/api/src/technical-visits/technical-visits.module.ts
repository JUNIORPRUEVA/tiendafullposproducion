import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { TechnicalVisitsController } from './technical-visits.controller';
import { TechnicalVisitsService } from './technical-visits.service';

@Module({
  imports: [PrismaModule],
  controllers: [TechnicalVisitsController],
  providers: [TechnicalVisitsService],
  exports: [TechnicalVisitsService],
})
export class TechnicalVisitsModule {}
