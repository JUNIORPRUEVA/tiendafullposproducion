import { Module } from '@nestjs/common';
import { OperationsService } from './operations-main.service';
import { OperationsController } from './operations.controller';
import { OperationsChecklistService } from './operations-checklist.service';
import { OperationsRealtimeService } from './operations-realtime.service';
import { NotificationsModule } from '../notifications/notifications.module';
import { StorageModule } from '../storage/storage.module';
import { ServiceClosingModule } from '../service-closing/service-closing.module';
import { ProductsModule } from '../products/products.module';

@Module({
  imports: [NotificationsModule, StorageModule, ServiceClosingModule, ProductsModule],
  controllers: [OperationsController],
  providers: [OperationsService, OperationsRealtimeService, OperationsChecklistService],
  exports: [OperationsService],
})
export class OperationsModule {}
