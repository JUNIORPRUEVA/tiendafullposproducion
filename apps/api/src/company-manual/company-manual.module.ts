import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { CompanyManualController } from './company-manual.controller';
import { CompanyManualService } from './company-manual.service';

@Module({
  imports: [PrismaModule],
  controllers: [CompanyManualController],
  providers: [CompanyManualService],
  exports: [CompanyManualService],
})
export class CompanyManualModule {}