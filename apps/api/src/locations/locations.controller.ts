import { Body, Controller, Post, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Request } from 'express';
import { Role } from '@prisma/client';
import { ReportLocationDto } from './dto/report-location.dto';
import { LocationsService } from './locations.service';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('locations')
export class LocationsController {
  constructor(private readonly locations: LocationsService) {}

  @Post()
  @Roles(Role.TECNICO)
  report(@Req() req: Request, @Body() dto: ReportLocationDto) {
    const user = req.user as { id?: string } | undefined;
    return this.locations.reportLocation(user?.id, dto);
  }
}
