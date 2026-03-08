import { Body, Controller, Get, Param, Post, Query, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Request } from 'express';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { SalidasTecnicasService } from './salidas-tecnicas.service';
import { AdminSalidasQueryDto } from './dto/admin-salidas-query.dto';
import { AdminAprobarRechazarDto, AdminRechazarDto } from './dto/admin-aprobar-rechazar.dto';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller()
export class AdminSalidasTecnicasController {
  constructor(private readonly salidas: SalidasTecnicasService) {}

  @Get('admin/salidas-tecnicas')
  @Roles(Role.ADMIN)
  list(@Query() query: AdminSalidasQueryDto) {
    return this.salidas.adminListSalidas(query);
  }

  @Post('admin/salidas-tecnicas/:id/aprobar')
  @Roles(Role.ADMIN)
  aprobar(@Req() req: Request, @Param('id') id: string, @Body() dto: AdminAprobarRechazarDto) {
    const actor = req.user as { id: string; role: Role };
    return this.salidas.adminAprobarSalida(actor.id, id, dto.observacion);
  }

  @Post('admin/salidas-tecnicas/:id/rechazar')
  @Roles(Role.ADMIN)
  rechazar(@Req() req: Request, @Param('id') id: string, @Body() dto: AdminRechazarDto) {
    const actor = req.user as { id: string; role: Role };
    return this.salidas.adminRechazarSalida(actor.id, id, dto.observacion);
  }
}
