import { Controller, Get, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Roles } from '../../auth/roles.decorator';
import { RolesGuard } from '../../auth/roles.guard';
import { AdminDiagnosticsService } from './admin-diagnostics.service';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Roles(Role.ADMIN)
@Controller('admin/diagnostics')
export class AdminDiagnosticsController {
  constructor(private readonly diagnostics: AdminDiagnosticsService) {}

  @Get('users-integrity')
  usersIntegrity() {
    return this.diagnostics.usersIntegrityReport();
  }
}
