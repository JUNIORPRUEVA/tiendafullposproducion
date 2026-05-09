import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { WhatsappModule } from '../whatsapp/whatsapp.module';
import { WhatsappInboxModule } from '../whatsapp-inbox/whatsapp-inbox.module';
import { CrmCommercialController } from './crm-commercial.controller';
import { CrmCommercialService } from './crm-commercial.service';

@Module({
  imports: [PrismaModule, WhatsappModule, WhatsappInboxModule],
  controllers: [CrmCommercialController],
  providers: [CrmCommercialService],
})
export class CrmCommercialModule {}
