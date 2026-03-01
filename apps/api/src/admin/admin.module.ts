import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { AdminPanelController } from './admin.controller';
import { AdminPanelService } from './admin.service';
import { AdminDiagnosticsController } from './diagnostics/admin-diagnostics.controller';
import { AdminDiagnosticsService } from './diagnostics/admin-diagnostics.service';

@Module({
  imports: [PrismaModule],
  controllers: [AdminPanelController, AdminDiagnosticsController],
  providers: [AdminPanelService, AdminDiagnosticsService],
})
export class AdminModule {}
