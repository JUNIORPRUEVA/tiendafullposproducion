import { Module } from '@nestjs/common';
import { SalesController } from './sales.controller';
import { SalesService } from './sales.service';
import { SalesAdminController } from './sales-admin.controller';

@Module({
  controllers: [SalesController, SalesAdminController],
  providers: [SalesService],
})
export class SalesModule {}
