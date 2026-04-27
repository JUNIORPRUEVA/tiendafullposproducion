import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { WhatsappService } from './whatsapp.service';
import { WhatsappController, WhatsappWebhookController } from './whatsapp.controller';

@Module({
  imports: [PrismaModule],
  providers: [WhatsappService],
  controllers: [WhatsappController, WhatsappWebhookController],
  exports: [WhatsappService],
})
export class WhatsappModule {}
