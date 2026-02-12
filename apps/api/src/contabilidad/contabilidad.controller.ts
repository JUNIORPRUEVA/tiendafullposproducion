import { Controller, Get, Post, Put, Delete, Body, Param, Query, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { RolesGuard } from '../auth/roles.guard';
import { Roles } from '../auth/roles.decorator';
import { ContabilidadService } from './contabilidad.service';
import { CreateCloseDto, UpdateCloseDto } from './close.dto';

@Controller('contabilidad')
@UseGuards(AuthGuard('jwt'), RolesGuard)
export class ContabilidadController {
  constructor(private readonly contabilidadService: ContabilidadService) {}

  @Post('closes')
  @Roles('ADMIN')
  async createClose(@Body() dto: CreateCloseDto) {
    return this.contabilidadService.createClose(dto);
  }

  @Get('closes')
  @Roles('ADMIN')
  async getCloses(@Query('date') date?: string) {
    return this.contabilidadService.getCloses(date);
  }

  @Get('closes/:id')
  @Roles('ADMIN')
  async getCloseById(@Param('id') id: string) {
    return this.contabilidadService.getCloseById(id);
  }

  @Put('closes/:id')
  @Roles('ADMIN')
  async updateClose(@Param('id') id: string, @Body() dto: UpdateCloseDto) {
    return this.contabilidadService.updateClose(id, dto);
  }

  @Delete('closes/:id')
  @Roles('ADMIN')
  async deleteClose(@Param('id') id: string) {
    return this.contabilidadService.deleteClose(id);
  }
}