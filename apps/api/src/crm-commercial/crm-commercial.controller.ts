import {
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Post,
  Query,
  Req,
  UnauthorizedException,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Request } from 'express';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { CrmCommercialService } from './crm-commercial.service';
import { ChangeCrmCommercialStatusDto } from './dto/change-crm-commercial-status.dto';
import { CreateCrmCommercialActivityDto } from './dto/create-crm-commercial-activity.dto';
import { CreateCrmCommercialCustomerDto } from './dto/create-crm-commercial-customer.dto';
import { CreateCrmCommercialNoteDto } from './dto/create-crm-commercial-note.dto';
import { CrmCommercialQueryDto } from './dto/crm-commercial-query.dto';
import { UpdateCrmCommercialCustomerDto } from './dto/update-crm-commercial-customer.dto';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('crm-commercial')
export class CrmCommercialController {
  constructor(private readonly crmCommercial: CrmCommercialService) {}

  private userOrThrow(req: Request) {
    const user = req.user as { id?: string; role?: Role } | undefined;
    if (!user?.id || !user.role) {
      throw new UnauthorizedException('Usuario no autenticado');
    }
    return { id: user.id, role: user.role };
  }

  @Post('customers')
  @Roles(Role.ADMIN)
  create(@Req() req: Request, @Body() dto: CreateCrmCommercialCustomerDto) {
    return this.crmCommercial.create(this.userOrThrow(req), dto);
  }

  @Get('customers')
  @Roles(Role.ADMIN)
  findAll(@Req() req: Request, @Query() query: CrmCommercialQueryDto) {
    return this.crmCommercial.findAll(this.userOrThrow(req), query);
  }

  @Get('customers/:id')
  @Roles(Role.ADMIN)
  findOne(@Req() req: Request, @Param('id') id: string) {
    return this.crmCommercial.findOne(this.userOrThrow(req), id);
  }

  @Patch('customers/:id')
  @Roles(Role.ADMIN)
  update(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() dto: UpdateCrmCommercialCustomerDto,
  ) {
    return this.crmCommercial.update(this.userOrThrow(req), id, dto);
  }

  @Patch('customers/:id/status')
  @Roles(Role.ADMIN)
  changeStatus(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() dto: ChangeCrmCommercialStatusDto,
  ) {
    return this.crmCommercial.changeStatus(this.userOrThrow(req), id, dto);
  }

  @Post('customers/:id/notes')
  @Roles(Role.ADMIN)
  addNote(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() dto: CreateCrmCommercialNoteDto,
  ) {
    return this.crmCommercial.addNote(this.userOrThrow(req), id, dto);
  }

  @Post('customers/:id/activities')
  @Roles(Role.ADMIN)
  addActivity(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() dto: CreateCrmCommercialActivityDto,
  ) {
    return this.crmCommercial.addActivity(this.userOrThrow(req), id, dto);
  }
}
