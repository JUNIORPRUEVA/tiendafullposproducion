import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { EvolutionWhatsAppService } from './evolution-whatsapp.service';
import { NotificationsDispatcher } from './notifications.dispatcher';
import { ServiceOrderInProgressReminderScheduler } from './service-order-in-progress-reminder.scheduler';
import { NotificationsService } from './notifications.service';
import { ServiceOrderNotificationJobsProcessor } from './service-order-notification-jobs.processor';
import { ServiceOrderNotificationsListener } from './service-order-notifications.listener';
import { ServiceOrderQuotationPdfService } from './service-order-quotation-pdf.service';

@Module({
  imports: [PrismaModule],
  providers: [
    EvolutionWhatsAppService,
    NotificationsService,
    NotificationsDispatcher,
    ServiceOrderInProgressReminderScheduler,
    ServiceOrderQuotationPdfService,
    ServiceOrderNotificationJobsProcessor,
    ServiceOrderNotificationsListener,
  ],
  exports: [
    NotificationsService,
    ServiceOrderNotificationsListener,
    EvolutionWhatsAppService,
  ],
})
export class NotificationsModule {}
