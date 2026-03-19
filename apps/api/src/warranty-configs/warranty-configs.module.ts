import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { WarrantyConfigsController } from './warranty-configs.controller';
import { WarrantyConfigsService } from './warranty-configs.service';

@Module({
  imports: [PrismaModule],
  controllers: [WarrantyConfigsController],
  providers: [WarrantyConfigsService],
  exports: [WarrantyConfigsService],
})
export class WarrantyConfigsModule {}