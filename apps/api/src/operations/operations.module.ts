import { Module } from '@nestjs/common';
import { OperationsService } from './operations-main.service';
import { OperationsController } from './operations.controller';
import { NotificationsModule } from '../notifications/notifications.module';
import { StorageModule } from '../storage/storage.module';
import { ServiceClosingModule } from '../service-closing/service-closing.module';

@Module({
  imports: [NotificationsModule, StorageModule, ServiceClosingModule],
  controllers: [OperationsController],
  providers: [OperationsService],
  exports: [OperationsService],
})
export class OperationsModule {}
