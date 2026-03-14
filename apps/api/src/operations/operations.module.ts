import { Module } from '@nestjs/common';
import { OperationsService } from './operations-main.service';
import { OperationsController } from './operations.controller';
import { NotificationsModule } from '../notifications/notifications.module';

@Module({
  imports: [NotificationsModule],
  controllers: [OperationsController],
  providers: [OperationsService],
  exports: [OperationsService],
})
export class OperationsModule {}
