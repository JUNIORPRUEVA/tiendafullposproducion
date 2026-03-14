import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { EvolutionWhatsAppService } from './evolution-whatsapp.service';
import { NotificationsDispatcher } from './notifications.dispatcher';
import { NotificationsService } from './notifications.service';

@Module({
  imports: [PrismaModule],
  providers: [EvolutionWhatsAppService, NotificationsService, NotificationsDispatcher],
  exports: [NotificationsService],
})
export class NotificationsModule {}
