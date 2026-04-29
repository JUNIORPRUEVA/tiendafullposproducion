import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { WhatsappInboxService } from './whatsapp-inbox.service';
import { WhatsappInboxController, WhatsappInboxWebhookController } from './whatsapp-inbox.controller';
import { WhatsappModule } from '../whatsapp/whatsapp.module';
import { ProductsModule } from '../products/products.module';

@Module({
  imports: [PrismaModule, WhatsappModule, ProductsModule],
  providers: [WhatsappInboxService],
  controllers: [WhatsappInboxController, WhatsappInboxWebhookController],
  exports: [WhatsappInboxService],
})
export class WhatsappInboxModule {}
