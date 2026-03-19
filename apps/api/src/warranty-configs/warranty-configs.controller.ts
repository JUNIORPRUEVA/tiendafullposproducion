import { Body, Controller, Delete, Get, Param, Patch, Post, Query, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Request } from 'express';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { SetWarrantyProductConfigActiveDto } from './dto/set-warranty-product-config-active.dto';
import { UpsertWarrantyProductConfigDto } from './dto/upsert-warranty-product-config.dto';
import { WarrantyProductConfigQueryDto } from './dto/warranty-product-config-query.dto';
import { WarrantyConfigsService } from './warranty-configs.service';

type JwtUser = { id: string; role: Role };

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('warranty-configs')
export class WarrantyConfigsController {
  constructor(private readonly warrantyConfigs: WarrantyConfigsService) {}

  @Get()
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  list(@Req() req: Request, @Query() query: WarrantyProductConfigQueryDto) {
    return this.warrantyConfigs.list(req.user as JwtUser, query);
  }

  @Get(':id')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  findOne(@Req() req: Request, @Param('id') id: string) {
    return this.warrantyConfigs.findOne(req.user as JwtUser, id);
  }

  @Post()
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR)
  create(@Req() req: Request, @Body() dto: UpsertWarrantyProductConfigDto) {
    return this.warrantyConfigs.create(req.user as JwtUser, dto);
  }

  @Patch(':id')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR)
  update(@Req() req: Request, @Param('id') id: string, @Body() dto: UpsertWarrantyProductConfigDto) {
    return this.warrantyConfigs.update(req.user as JwtUser, id, dto);
  }

  @Patch(':id/active')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR)
  setActive(@Req() req: Request, @Param('id') id: string, @Body() dto: SetWarrantyProductConfigActiveDto) {
    return this.warrantyConfigs.setActive(req.user as JwtUser, id, dto.isActive);
  }

  @Delete(':id')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR)
  remove(@Req() req: Request, @Param('id') id: string) {
    return this.warrantyConfigs.remove(req.user as JwtUser, id);
  }
}