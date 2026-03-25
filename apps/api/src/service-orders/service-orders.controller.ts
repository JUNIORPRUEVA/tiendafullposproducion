import { Body, Controller, Delete, Get, Param, Patch, Post, Query, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Request } from 'express';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { CloneServiceOrderDto } from './dto/clone-service-order.dto';
import { CreateEvidenceDto } from './dto/create-evidence.dto';
import { CreateReportDto } from './dto/create-report.dto';
import { CreateServiceOrderDto } from './dto/create-service-order.dto';
import { ServiceOrderSalesSummaryQueryDto } from './dto/service-order-sales-summary-query.dto';
import { UpdateServiceOrderDto } from './dto/update-service-order.dto';
import { UpdateStatusDto } from './dto/update-status.dto';
import { ServiceOrdersService } from './service-orders.service';

type JwtUser = { id: string; role: Role };

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('service-orders')
export class ServiceOrdersController {
  constructor(private readonly serviceOrders: ServiceOrdersService) {}

  @Post()
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO, Role.MARKETING)
  create(@Req() req: Request, @Body() dto: CreateServiceOrderDto) {
    return this.serviceOrders.create(req.user as JwtUser, dto);
  }

  @Get()
  list(@Req() req: Request) {
    return this.serviceOrders.list(req.user as JwtUser);
  }

  @Get('sales-summary')
  salesSummary(@Req() req: Request, @Query() query: ServiceOrderSalesSummaryQueryDto) {
    return this.serviceOrders.salesSummary(req.user as JwtUser, query.from, query.to);
  }

  @Get(':id')
  findOne(@Req() req: Request, @Param('id') id: string) {
    return this.serviceOrders.findOne(req.user as JwtUser, id);
  }

  @Patch(':id')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO, Role.MARKETING)
  update(@Req() req: Request, @Param('id') id: string, @Body() dto: UpdateServiceOrderDto) {
    return this.serviceOrders.update(req.user as JwtUser, id, dto);
  }

  @Patch(':id/status')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO, Role.MARKETING)
  updateStatus(@Req() req: Request, @Param('id') id: string, @Body() dto: UpdateStatusDto) {
    return this.serviceOrders.updateStatus(req.user as JwtUser, id, dto);
  }

  @Post(':id/evidences')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  addEvidence(@Req() req: Request, @Param('id') id: string, @Body() dto: CreateEvidenceDto) {
    return this.serviceOrders.addEvidence(req.user as JwtUser, id, dto);
  }

  @Post(':id/report')
  @Roles(Role.ADMIN, Role.TECNICO)
  addReport(@Req() req: Request, @Param('id') id: string, @Body() dto: CreateReportDto) {
    return this.serviceOrders.addReport(req.user as JwtUser, id, dto);
  }

  @Post(':id/clone')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR)
  clone(@Req() req: Request, @Param('id') id: string, @Body() dto: CloneServiceOrderDto) {
    return this.serviceOrders.clone(req.user as JwtUser, id, dto);
  }

  @Delete(':id')
  @Roles(Role.ADMIN)
  remove(@Req() req: Request, @Param('id') id: string) {
    return this.serviceOrders.remove(req.user as JwtUser, id);
  }
}
