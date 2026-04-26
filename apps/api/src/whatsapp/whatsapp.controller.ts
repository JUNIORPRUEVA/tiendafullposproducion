import {
  Body,
  Controller,
  Delete,
  Get,
  Post,
  Req,
  UseGuards,
} from '@nestjs/common';
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
}
