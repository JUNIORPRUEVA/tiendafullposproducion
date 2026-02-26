import { Body, Controller, Delete, Get, Param, Post, Query, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Request } from 'express';
import { SalesService } from './sales.service';
import { CreateSaleDto } from './dto/create-sale.dto';
import { SalesRangeQueryDto } from './dto/sales-range-query.dto';

@UseGuards(AuthGuard('jwt'))
@Controller('sales')
export class SalesController {
  constructor(private readonly sales: SalesService) {}

  @Get()
  listMine(@Req() req: Request, @Query() query: SalesRangeQueryDto) {
    const user = req.user as { id: string; role: string };
    return this.sales.listMine(user.id, query.from, query.to);
  }

  @Get('summary')
  summaryMine(@Req() req: Request, @Query() query: SalesRangeQueryDto) {
    const user = req.user as { id: string; role: string };
    return this.sales.summaryMine(user.id, query.from, query.to);
  }

  @Post()
  create(@Req() req: Request, @Body() dto: CreateSaleDto) {
    const user = req.user as { id: string; role: string };
    return this.sales.create(user.id, dto);
  }

  @Delete(':id')
  remove(@Req() req: Request, @Param('id') id: string) {
    const user = req.user as { id: string; role: string };
    return this.sales.remove(user.id, id);
  }
}
