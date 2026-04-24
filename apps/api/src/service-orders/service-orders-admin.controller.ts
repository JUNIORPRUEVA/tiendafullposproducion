import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { AdminServiceOrderCommissionsQueryDto } from './dto/admin-service-order-commissions-query.dto';
import { ServiceOrdersService } from './service-orders.service';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Roles(Role.ADMIN)
@Controller('admin/service-commissions')
export class ServiceOrdersAdminController {
  constructor(private readonly serviceOrders: ServiceOrdersService) {}

  @Get()
  listByUser(@Query() query: AdminServiceOrderCommissionsQueryDto) {
    return this.serviceOrders.adminListCommissionsByUser(
      query.userId,
      query.from,
      query.to,
    );
  }

  @Get('summary')
  summaryByUser(@Query() query: AdminServiceOrderCommissionsQueryDto) {
    return this.serviceOrders.adminCommissionSummaryByUser(
      query.from,
      query.to,
      query.userId,
    );
  }
}