import { Module } from '@nestjs/common';
import { SalesService } from './sales.service';
import { SalesAdminController, SalesController } from './sales.controller';

@Module({
  providers: [SalesService],
  controllers: [SalesController, SalesAdminController]
})
export class SalesModule {}

