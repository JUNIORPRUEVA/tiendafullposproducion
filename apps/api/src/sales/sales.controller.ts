import { Body, Controller, Delete, Get, Param, Post, Put, Query, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Request } from 'express';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { AdminSalesQueryDto } from './dto/admin-sales-query.dto';
import { CreateSaleDto } from './dto/create-sale.dto';
import { CreateSaleItemDto } from './dto/create-sale-item.dto';
import { SalesQueryDto } from './dto/sales-query.dto';
import { UpdateSaleDto } from './dto/update-sale.dto';
import { UpdateSaleItemDto } from './dto/update-sale-item.dto';
import { SalesService } from './sales.service';

const asUser = (req: Request) => req.user as any;

@UseGuards(AuthGuard('jwt'))
@Controller('sales')
export class SalesController {
  constructor(private readonly sales: SalesService) {}

  @Post()
  create(@Req() req: Request, @Body() dto: CreateSaleDto) {
    const user = asUser(req);
    return this.sales.createSale(user, dto);
  }

  @Post(':id/items')
  addItem(@Req() req: Request, @Param('id') id: string, @Body() dto: CreateSaleItemDto) {
    const user = asUser(req);
    return this.sales.addItem(user, id, dto);
  }

  @Put(':id/items/:itemId')
  updateItem(
    @Req() req: Request,
    @Param('id') id: string,
    @Param('itemId') itemId: string,
    @Body() dto: UpdateSaleItemDto
  ) {
    const user = asUser(req);
    return this.sales.updateItem(user, id, itemId, dto);
  }

  @Delete(':id/items/:itemId')
  removeItem(@Req() req: Request, @Param('id') id: string, @Param('itemId') itemId: string) {
    const user = asUser(req);
    return this.sales.removeItem(user, id, itemId);
  }

  @Put(':id')
  updateSale(@Req() req: Request, @Param('id') id: string, @Body() dto: UpdateSaleDto) {
    const user = asUser(req);
    return this.sales.updateSale(user, id, dto);
  }

  @Delete(':id')
  deleteSale(@Req() req: Request, @Param('id') id: string) {
    const user = asUser(req);
    return this.sales.deleteSale(user, id);
  }

  @Get('me')
  listMine(@Req() req: Request, @Query() q: SalesQueryDto) {
    const user = asUser(req);
    return this.sales.listMine(user, q);
  }

  @Get(':id')
  getOne(@Req() req: Request, @Param('id') id: string) {
    const user = asUser(req);
    return this.sales.findByIdForUser(user, id);
  }
}

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Roles(Role.ADMIN)
@Controller('admin/sales')
export class SalesAdminController {
  constructor(private readonly sales: SalesService) {}

  @Get()
  list(@Query() q: AdminSalesQueryDto) {
    return this.sales.adminList(q);
  }

  @Get('summary')
  summary(@Query() q: AdminSalesQueryDto) {
    return this.sales.adminSummary(q);
  }

  @Get(':id')
  getOne(@Param('id') id: string) {
    return this.sales.findByIdForUser({ id: 'admin', role: Role.ADMIN }, id);
  }
}

