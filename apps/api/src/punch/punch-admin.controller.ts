import { Controller, Get, Param, Query, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { AdminPunchQueryDto } from './dto/admin-punch-query.dto';
import { AttendanceSummaryQueryDto } from './dto/attendance-summary-query.dto';
import { AttendanceUserQueryDto } from './dto/attendance-user-query.dto';
import { PunchService } from './punch.service';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Roles(Role.ADMIN)
@Controller('admin/punch')
export class PunchAdminController {
  constructor(private readonly punch: PunchService) {}

  @Get()
  list(@Query() query: AdminPunchQueryDto) {
    return this.punch.listAdmin(query.userId, query.from, query.to);
  }

  @Get('attendance/summary')
  summary(@Query() query: AttendanceSummaryQueryDto) {
    return this.punch.attendanceSummary(query);
  }

  @Get('attendance/user/:id')
  userDetail(@Param('id') id: string, @Query() query: AttendanceUserQueryDto) {
    return this.punch.attendanceDetail(id, query);
  }
}
