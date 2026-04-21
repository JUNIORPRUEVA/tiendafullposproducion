import { Module } from '@nestjs/common';
import { RedisModule } from '../common/redis/redis.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { OrderDocumentFlowModule } from '../order-document-flow/order-document-flow.module';
import { PayrollModule } from '../payroll/payroll.module';
import { PrismaModule } from '../prisma/prisma.module';
import { ProductsModule } from '../products/products.module';
import { ServiceOrdersController } from './service-orders.controller';
import { ServiceOrderPostponedResetScheduler } from './service-order-postponed-reset.scheduler';
import { ServiceOrdersService } from './service-orders.service';

@Module({
  imports: [PrismaModule, RedisModule, ProductsModule, PayrollModule, NotificationsModule, OrderDocumentFlowModule],
  controllers: [ServiceOrdersController],
  providers: [ServiceOrdersService, ServiceOrderPostponedResetScheduler],
  exports: [ServiceOrdersService],
})
export class ServiceOrdersModule {}