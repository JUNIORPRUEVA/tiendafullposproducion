import { Module } from '@nestjs/common';
import { NotificationsModule } from '../notifications/notifications.module';
import { StorageModule } from '../storage/storage.module';
import { ContabilidadController } from './contabilidad.controller';
import { ContabilidadPublicController } from './contabilidad-public.controller';
import { ContabilidadService } from './contabilidad.service';

@Module({
  imports: [StorageModule, NotificationsModule],
  controllers: [ContabilidadController, ContabilidadPublicController],
  providers: [ContabilidadService],
})
export class ContabilidadModule {}
