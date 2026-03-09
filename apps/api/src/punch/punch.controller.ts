import { Body, Controller, Get, Post, Query, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Request } from 'express';
import { CreatePunchDto } from './dto/create-punch.dto';
import { AttendanceUserQueryDto } from './dto/attendance-user-query.dto';
import { PunchQueryDto } from './dto/punch-query.dto';
import { PunchService } from './punch.service';

@UseGuards(AuthGuard('jwt'))
@Controller('punch')
export class PunchController {
  constructor(private readonly punch: PunchService) {}

  @Post()
  create(@Req() req: Request, @Body() dto: CreatePunchDto) {
    const user = req.user as any;
    return this.punch.create(user.id, dto.type);
  }

  @Get('me')
  listMine(@Req() req: Request, @Query() query: PunchQueryDto) {
    const user = req.user as any;
    return this.punch.listMine(user.id, query.from, query.to);
  }

  @Get('me/attendance')
  myAttendance(@Req() req: Request, @Query() query: AttendanceUserQueryDto) {
    const user = req.user as any;
    return this.punch.myAttendanceDetail(user.id, query);
  }
}
