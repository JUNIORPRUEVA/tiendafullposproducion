import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { AdminPanelController } from './admin.controller';
import { AdminPanelService } from './admin.service';

@Module({
  imports: [PrismaModule],
  controllers: [AdminPanelController],
  providers: [AdminPanelService],
})
export class AdminModule {}
