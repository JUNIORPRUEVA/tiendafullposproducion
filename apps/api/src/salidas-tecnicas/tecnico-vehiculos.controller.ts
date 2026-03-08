import { Body, Controller, Get, Param, Patch, Post, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Request } from 'express';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { SalidasTecnicasService } from './salidas-tecnicas.service';
import { CreateVehiculoPropioDto } from './dto/create-vehiculo-propio.dto';
import { UpdateVehiculoPropioDto } from './dto/update-vehiculo-propio.dto';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller()
export class TecnicoVehiculosController {
  constructor(private readonly salidas: SalidasTecnicasService) {}

  @Get('tecnico/vehiculos')
  @Roles(Role.TECNICO)
  list(@Req() req: Request) {
    const user = req.user as { id: string; role: Role };
    return this.salidas.listVehiculosForTecnico(user.id);
  }

  @Post('tecnico/vehiculos')
  @Roles(Role.TECNICO)
  create(@Req() req: Request, @Body() dto: CreateVehiculoPropioDto) {
    const user = req.user as { id: string; role: Role };
    return this.salidas.createVehiculoPropio(user.id, dto);
  }

  @Patch('tecnico/vehiculos/:id')
  @Roles(Role.TECNICO)
  update(@Req() req: Request, @Param('id') id: string, @Body() dto: UpdateVehiculoPropioDto) {
    const user = req.user as { id: string; role: Role };
    return this.salidas.updateVehiculoPropio(user.id, id, dto);
  }
}
