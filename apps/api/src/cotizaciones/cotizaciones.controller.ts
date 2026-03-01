import { Body, Controller, Delete, Get, Param, Patch, Post, Query, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Request } from 'express';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { CotizacionesService } from './cotizaciones.service';
import { CotizacionesQueryDto } from './dto/cotizaciones-query.dto';
import { CreateCotizacionDto } from './dto/create-cotizacion.dto';
import { UpdateCotizacionDto } from './dto/update-cotizacion.dto';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('cotizaciones')
export class CotizacionesController {
  constructor(private readonly cotizaciones: CotizacionesService) {}

  @Get()
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  list(@Req() req: Request, @Query() query: CotizacionesQueryDto) {
    const user = req.user as { id: string; role: Role };
    return this.cotizaciones.list(user, query);
  }

  @Get(':id')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  getOne(@Req() req: Request, @Param('id') id: string) {
    const user = req.user as { id: string; role: Role };
    return this.cotizaciones.findOne(user, id);
  }

  @Post()
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR)
  create(@Req() req: Request, @Body() dto: CreateCotizacionDto) {
    const user = req.user as { id: string; role: Role };
    return this.cotizaciones.create(user, dto);
  }

  @Patch(':id')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR)
  update(@Req() req: Request, @Param('id') id: string, @Body() dto: UpdateCotizacionDto) {
    const user = req.user as { id: string; role: Role };
    return this.cotizaciones.update(user, id, dto);
  }

  @Delete(':id')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR)
  remove(@Req() req: Request, @Param('id') id: string) {
    const user = req.user as { id: string; role: Role };
    return this.cotizaciones.remove(user, id);
  }
}
