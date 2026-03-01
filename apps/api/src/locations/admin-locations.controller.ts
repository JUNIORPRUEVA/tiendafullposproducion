import { Controller, Get, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { LocationsService } from './locations.service';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Roles(Role.ADMIN)
@Controller('admin/locations')
export class AdminLocationsController {
  constructor(private readonly locations: LocationsService) {}

  @Get('latest')
  latest() {
    return this.locations.listLatestLocationsForAdmin();
  }
}
