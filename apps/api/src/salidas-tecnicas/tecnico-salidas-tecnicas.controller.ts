import { Body, Controller, Get, Param, Patch, Post, Query, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Request } from 'express';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { SalidasTecnicasService } from './salidas-tecnicas.service';
import { IniciarSalidaTecnicaDto } from './dto/iniciar-salida-tecnica.dto';
import { MarcarLlegadaDto } from './dto/marcar-llegada.dto';
import { FinalizarSalidaDto } from './dto/finalizar-salida.dto';
import { SalidasQueryDto } from './dto/salidas-query.dto';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller()
export class TecnicoSalidasTecnicasController {
  constructor(private readonly salidas: SalidasTecnicasService) {}

  @Get('tecnico/salidas-tecnicas/abierta')
  @Roles(Role.TECNICO)
  getAbierta(@Req() req: Request) {
    const user = req.user as { id: string; role: Role };
    return this.salidas.getSalidaAbierta(user.id);
  }

  @Get('tecnico/salidas-tecnicas/historial')
  @Roles(Role.TECNICO)
  historial(@Req() req: Request, @Query() query: SalidasQueryDto) {
    const user = req.user as { id: string; role: Role };
    return this.salidas.listMisSalidas(user.id, query);
  }

  @Post('tecnico/salidas-tecnicas/iniciar')
  @Roles(Role.TECNICO)
  iniciar(@Req() req: Request, @Body() dto: IniciarSalidaTecnicaDto) {
    const user = req.user as { id: string; role: Role };
    return this.salidas.iniciarSalidaTecnica({
      tecnicoId: user.id,
      servicioId: dto.servicioId,
      vehiculoId: dto.vehiculoId,
      esVehiculoPropio: dto.esVehiculoPropio,
      latSalida: dto.latSalida,
      lngSalida: dto.lngSalida,
      observacion: dto.observacion,
    });
  }

  @Patch('tecnico/salidas-tecnicas/:id/llegada')
  @Roles(Role.TECNICO)
  llegada(@Req() req: Request, @Param('id') id: string, @Body() dto: MarcarLlegadaDto) {
    const user = req.user as { id: string; role: Role };
    return this.salidas.marcarLlegada({
      tecnicoId: user.id,
      salidaId: id,
      latLlegada: dto.latLlegada,
      lngLlegada: dto.lngLlegada,
      observacion: dto.observacion,
    });
  }

  @Patch('tecnico/salidas-tecnicas/:id/finalizar')
  @Roles(Role.TECNICO)
  finalizar(@Req() req: Request, @Param('id') id: string, @Body() dto: FinalizarSalidaDto) {
    const user = req.user as { id: string; role: Role };
    return this.salidas.finalizarSalida({
      tecnicoId: user.id,
      salidaId: id,
      latFinal: dto.latFinal,
      lngFinal: dto.lngFinal,
      observacion: dto.observacion,
    });
  }
}
