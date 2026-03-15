import { Body, Controller, Get, Param, Patch, Post, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Request } from 'express';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { ServiceClosingService } from './service-closing.service';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller()
export class ServiceClosingController {
  constructor(private readonly closing: ServiceClosingService) {}

  @Get('services/:id/closing')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  getClosing(@Req() req: Request, @Param('id') id: string) {
    const user = req.user as { id: string; role: Role };
    return this.closing.getClosing(user, id);
  }

  @Post('services/:id/closing/start')
  @Roles(Role.ADMIN, Role.ASISTENTE)
  start(@Req() req: Request, @Param('id') id: string) {
    const user = req.user as { id: string; role: Role };
    return this.closing.tryStartOnServiceFinalized({ serviceId: id, triggeredByUserId: user.id });
  }

  @Patch('services/:id/closing/draft')
  @Roles(Role.ADMIN, Role.ASISTENTE)
  updateDraft(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() body: { invoiceData?: any; warrantyData?: any },
  ) {
    const user = req.user as { id: string; role: Role };
    return this.closing.updateDraft(user, id, body);
  }

  @Post('services/:id/closing/approve')
  @Roles(Role.ADMIN, Role.ASISTENTE)
  approve(@Req() req: Request, @Param('id') id: string) {
    const user = req.user as { id: string; role: Role };
    return this.closing.approve(user, id);
  }

  @Post('services/:id/closing/reject')
  @Roles(Role.ADMIN, Role.ASISTENTE)
  reject(@Req() req: Request, @Param('id') id: string, @Body() body: { reason?: string }) {
    const user = req.user as { id: string; role: Role };
    return this.closing.reject(user, id, body?.reason);
  }

  @Post('services/:id/closing/finalize')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.TECNICO)
  finalize(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() body: { skipSignature?: boolean },
  ) {
    const user = req.user as { id: string; role: Role };
    return this.closing.finalizeAndSendToClient(user, id, { skipSignature: !!body?.skipSignature });
  }
}
