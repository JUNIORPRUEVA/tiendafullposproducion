import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { OrderDocumentFlowController } from './order-document-flow.controller';
import { OrderDocumentFlowService } from './order-document-flow.service';

@Module({
  imports: [PrismaModule],
  controllers: [OrderDocumentFlowController],
  providers: [OrderDocumentFlowService],
  exports: [OrderDocumentFlowService],
})
export class OrderDocumentFlowModule {}