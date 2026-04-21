import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { isWithinNotificationBusinessHours } from './notification-business-hours.util';
import { ServiceOrderNotificationsListener } from './service-order-notifications.listener';

@Injectable()
export class ServiceOrderInProgressReminderScheduler {
  private readonly logger = new Logger(ServiceOrderInProgressReminderScheduler.name);

  constructor(private readonly listener: ServiceOrderNotificationsListener) {}

  @Cron(CronExpression.EVERY_5_MINUTES)
  async dispatchDueInProgressReminders() {
    if (!isWithinNotificationBusinessHours()) {
      return;
    }

    const processed = await this.listener.processDueInProgressReminders();
    if (processed > 0) {
      this.logger.log(`Processed ${processed} in-progress reminder notifications`);
    }
  }
}