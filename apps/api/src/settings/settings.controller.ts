import { Body, Controller, Get, Patch, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Request } from 'express';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { UpdateSettingsDto } from './dto/update-settings.dto';
import { SettingsService } from './settings.service';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('settings')
export class SettingsController {
  constructor(private readonly settings: SettingsService) {}

  @Get()
  getSettings(@Req() req: Request) {
    return this.settings.getSettings(req.user as { role?: Role | string } | undefined);
  }

  @Patch()
  @Roles(Role.ADMIN)
  updateSettings(@Body() dto: UpdateSettingsDto, @Req() req: Request) {
    return this.settings.updateSettings(
      dto,
      req.user as { role?: Role | string } | undefined,
    );
  }
}
