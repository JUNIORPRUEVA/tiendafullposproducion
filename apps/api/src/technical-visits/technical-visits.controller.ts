import { Body, Controller, Get, Param, Patch, Post, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Request } from 'express';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { CreateTechnicalVisitDto } from './dto/create-technical-visit.dto';
import { UpdateTechnicalVisitDto } from './dto/update-technical-visit.dto';
import { TechnicalVisitsService } from './technical-visits.service';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller()
export class TechnicalVisitsController {
  constructor(private readonly visits: TechnicalVisitsService) {}

  @Post('technical-visits')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  create(@Req() req: Request, @Body() body: CreateTechnicalVisitDto) {
    const user = req.user as { id: string; role: Role };
    return this.visits.create(user, body);
  }

  @Get('technical-visits/order/:orderId')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  getByOrder(@Req() req: Request, @Param('orderId') orderId: string) {
    const user = req.user as { id: string; role: Role };
    return this.visits.getByOrder(user, orderId);
  }

  @Patch('technical-visits/:id')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  update(@Req() req: Request, @Param('id') id: string, @Body() body: UpdateTechnicalVisitDto) {
    const user = req.user as { id: string; role: Role };
    return this.visits.update(user, id, body);
  }
}
