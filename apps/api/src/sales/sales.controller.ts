import { Body, Controller, Get, Post, Query, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Request } from 'express';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { CreateSaleDto } from './dto/create-sale.dto';
import { SalesQueryDto } from './dto/sales-query.dto';
import { SalesService } from './sales.service';

@UseGuards(AuthGuard('jwt'))
@Controller('sales')
export class SalesController {
  constructor(private readonly sales: SalesService) {}

  @Post()
  create(@Req() req: Request, @Body() dto: CreateSaleDto) {
    const user = req.user as any;
    return this.sales.create(user.id, dto);
  }

  @Get()
  listMine(@Req() req: Request, @Query() q: SalesQueryDto) {
    const user = req.user as any;
    return this.sales.listMine(user.id, q.from, q.to);
  }

  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Get('all')
  listAll(@Query() q: SalesQueryDto) {
    return this.sales.listAll(q.from, q.to);
  }
}

