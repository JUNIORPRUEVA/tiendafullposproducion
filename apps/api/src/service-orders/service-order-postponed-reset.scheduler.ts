import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { ServiceOrdersService } from './service-orders.service';

@Injectable()
export class ServiceOrderPostponedResetScheduler {
  private readonly logger = new Logger(ServiceOrderPostponedResetScheduler.name);

  constructor(private readonly serviceOrders: ServiceOrdersService) {}

  @Cron(CronExpression.EVERY_5_MINUTES)
  async restoreDuePostponedOrders() {
    const result = await this.serviceOrders.restoreDuePostponedOrders();
    if (result.processed > 0) {
      this.logger.log(`Restored ${result.processed} postponed service orders to pending`);
    }
  }
}