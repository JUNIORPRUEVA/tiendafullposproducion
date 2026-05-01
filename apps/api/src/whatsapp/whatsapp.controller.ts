import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Req,
  UseGuards,
} from '@nestjs/common';
import { IsBoolean, IsNotEmpty, IsString } from 'class-validator';

class SetInstanceWebhookDto {
  @IsString()
  @IsNotEmpty()
  instanceName!: string;

  @IsBoolean()
  enabled!: boolean;
}
import { AuthGuard } from '@nestjs/passport';
import { Request } from 'express';
import { RolesGuard } from '../auth/roles.guard';
import { Roles } from '../auth/roles.decorator';
import { Role } from '@prisma/client';
import { WhatsappService } from './whatsapp.service';
import { CreateWhatsappInstanceDto } from './dto/create-whatsapp-instance.dto';

@Controller('whatsapp')
@UseGuards(AuthGuard('jwt'))
export class WhatsappController {
  constructor(private readonly whatsapp: WhatsappService) {}

  @Post('instance')
  createInstance(
    @Req() req: Request,
    @Body() dto: CreateWhatsappInstanceDto,
  ) {
    const user = req.user as { id: string };
    return this.whatsapp.createInstance(user.id, dto);
  }

  @Get('instance/status')
  getInstanceStatus(@Req() req: Request) {
    const user = req.user as { id: string };
    return this.whatsapp.getInstanceStatus(user.id);
  }

  @Get('instance/qr')
  getQrCode(@Req() req: Request) {
    const user = req.user as { id: string };
    return this.whatsapp.getQrCode(user.id);
  }

  @Delete('instance')
  deleteInstance(@Req() req: Request) {
    const user = req.user as { id: string };
    return this.whatsapp.deleteInstance(user.id);
  }

  @Get('admin/users')
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  listAdminUsers() {
    return this.whatsapp.listUsersWithWhatsappStatus();
  }

  // ─── Company instance ──────────────────────────────────────────────────

  @Post('company-instance')
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  createCompanyInstance(@Body() dto: CreateWhatsappInstanceDto) {
    return this.whatsapp.createCompanyInstance(dto);
  }

  @Get('company-instance/status')
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  getCompanyInstanceStatus() {
    return this.whatsapp.getCompanyInstanceStatus();
  }

  @Get('company-instance/qr')
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  getCompanyInstanceQr() {
    return this.whatsapp.getCompanyInstanceQr();
  }

  @Delete('company-instance')
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  deleteCompanyInstance() {
    return this.whatsapp.deleteCompanyInstance();
  }

  // ─── CRM admin: all instances + per-instance webhook ──────────────────

  @Get('admin/all-instances')
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  listAllInstancesForCrm() {
    return this.whatsapp.listAllInstancesForCrm();
  }

  @Patch('admin/instance-webhook')
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  setInstanceWebhook(@Body() dto: SetInstanceWebhookDto) {
    return this.whatsapp.setInstanceWebhookForAdmin(dto.instanceName, dto.enabled);
  }
}

@Controller('whatsapp/webhook')
export class WhatsappWebhookController {
  constructor(private readonly whatsapp: WhatsappService) {}

  @Post(':instanceName/:eventName')
  @Post(':instanceName')
  receiveWebhook(
    @Param('instanceName') instanceName: string,
    @Param('eventName') eventName: string | undefined,
    @Body() payload: unknown,
  ) {
    return this.whatsapp.handleIncomingWebhook(instanceName, payload, eventName);
  }
}
