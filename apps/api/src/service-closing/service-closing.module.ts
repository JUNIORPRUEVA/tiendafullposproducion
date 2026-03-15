import { Module } from '@nestjs/common';
import { NotificationsModule } from '../notifications/notifications.module';
import { StorageModule } from '../storage/storage.module';
import { ServiceClosingController } from './service-closing.controller';
import { ServiceClosingService } from './service-closing.service';

@Module({
  imports: [NotificationsModule, StorageModule],
  controllers: [ServiceClosingController],
  providers: [ServiceClosingService],
  exports: [ServiceClosingService],
})
export class ServiceClosingModule {}
