import { Module } from '@nestjs/common';
import { AttendanceAdminController } from './attendance-admin.controller';
import { PunchAdminController } from './punch-admin.controller';
import { PunchController } from './punch.controller';
import { PunchService } from './punch.service';

@Module({
  controllers: [PunchController, PunchAdminController, AttendanceAdminController],
  providers: [PunchService]
})
export class PunchModule {}
