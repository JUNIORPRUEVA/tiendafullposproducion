import { Body, Controller, Get, Param, Post, Query, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Request } from 'express';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { SalidasTecnicasService } from './salidas-tecnicas.service';
import { AdminCrearPagoPeriodoDto } from './dto/admin-crear-pago-periodo.dto';
import { AdminMarcarPagoPagadoDto } from './dto/admin-marcar-pago-pagado.dto';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller()
export class AdminPagosCombustibleController {
  constructor(private readonly salidas: SalidasTecnicasService) {}

  @Get('tecnico/pagos-combustible-tecnicos')
  @Roles(Role.TECNICO)
  misPagos(@Req() req: Request) {
    const user = req.user as { id: string; role: Role };
    return this.salidas.listMisPagosCombustible(user.id);
  }

  @Get('admin/pagos-combustible-tecnicos')
  @Roles(Role.ADMIN)
  listAdmin(@Query('tecnicoId') tecnicoId?: string) {
    return this.salidas.listPagosAdmin(tecnicoId);
  }

  @Post('admin/pagos-combustible-tecnicos')
  @Roles(Role.ADMIN)
  crearPeriodo(@Req() req: Request, @Body() dto: AdminCrearPagoPeriodoDto) {
    const actor = req.user as { id: string; role: Role };
    return this.salidas.adminCrearPagoPeriodo(actor.id, dto.tecnicoId, dto.fechaInicio, dto.fechaFin);
  }

  @Post('admin/pagos-combustible-tecnicos/:id/pagado')
  @Roles(Role.ADMIN)
  marcarPagado(@Req() req: Request, @Param('id') id: string, @Body() dto: AdminMarcarPagoPagadoDto) {
    const actor = req.user as { id: string; role: Role };
    return this.salidas.adminMarcarPagoPagado(actor.id, id, dto.fechaPago);
  }
}
