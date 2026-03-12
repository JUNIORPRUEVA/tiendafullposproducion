import { Body, Controller, Delete, Get, Param, Patch, Post, Query, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Request } from 'express';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { CompanyManualService } from './company-manual.service';
import { CompanyManualQueryDto } from './dto/company-manual-query.dto';
import { CompanyManualSummaryDto } from './dto/company-manual-summary.dto';
import { UpsertCompanyManualDto } from './dto/upsert-company-manual.dto';

type JwtUser = { id: string; role: Role };

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('company-manual')
export class CompanyManualController {
  constructor(private readonly companyManual: CompanyManualService) {}

  @Get()
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.MARKETING, Role.TECNICO)
  list(@Req() req: Request, @Query() query: CompanyManualQueryDto) {
    return this.companyManual.list(req.user as JwtUser, query);
  }

  @Get('summary')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.MARKETING, Role.TECNICO)
  summary(@Req() req: Request, @Query() query: CompanyManualSummaryDto) {
    return this.companyManual.summary(req.user as JwtUser, query.seenAt);
  }

  @Get(':id')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.MARKETING, Role.TECNICO)
  getOne(@Req() req: Request, @Param('id') id: string) {
    return this.companyManual.findOne(req.user as JwtUser, id);
  }

  @Post()
  @Roles(Role.ADMIN)
  create(@Req() req: Request, @Body() dto: UpsertCompanyManualDto) {
    return this.companyManual.upsert(req.user as JwtUser, dto);
  }

  @Patch(':id')
  @Roles(Role.ADMIN)
  update(@Req() req: Request, @Param('id') id: string, @Body() dto: UpsertCompanyManualDto) {
    return this.companyManual.upsert(req.user as JwtUser, { ...dto, id });
  }

  @Delete(':id')
  @Roles(Role.ADMIN)
  remove(@Req() req: Request, @Param('id') id: string) {
    return this.companyManual.remove(req.user as JwtUser, id);
  }
}