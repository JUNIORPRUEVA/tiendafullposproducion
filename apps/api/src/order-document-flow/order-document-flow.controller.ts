import { Controller, Get, Param, Patch, Post, Body, Query, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Request } from 'express';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { EditOrderDocumentFlowDraftDto } from './dto/edit-order-document-flow-draft.dto';
import { ListOrderDocumentFlowsQueryDto } from './dto/list-order-document-flows-query.dto';
import { SendOrderDocumentFlowDto } from './dto/send-order-document-flow.dto';
import { OrderDocumentFlowService } from './order-document-flow.service';

type JwtUser = { id: string; role: Role };

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('document-flows')
export class OrderDocumentFlowController {
  constructor(private readonly documentFlows: OrderDocumentFlowService) {}

  @Get()
  @Roles(Role.ADMIN, Role.ASISTENTE)
  list(@Req() req: Request, @Query() query: ListOrderDocumentFlowsQueryDto) {
    return this.documentFlows.list(req.user as JwtUser, query.status);
  }

  @Get(':orderId')
  @Roles(Role.ADMIN, Role.ASISTENTE)
  findByOrderId(@Req() req: Request, @Param('orderId') orderId: string) {
    return this.documentFlows.findByOrderId(req.user as JwtUser, orderId);
  }

  @Patch(':id/edit-draft')
  @Roles(Role.ADMIN, Role.ASISTENTE)
  editDraft(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() dto: EditOrderDocumentFlowDraftDto,
  ) {
    return this.documentFlows.editDraft(req.user as JwtUser, id, dto);
  }

  @Post(':id/generate')
  @Roles(Role.ADMIN, Role.ASISTENTE)
  generate(@Req() req: Request, @Param('id') id: string) {
    return this.documentFlows.generate(req.user as JwtUser, id);
  }

  @Post(':id/send')
  @Roles(Role.ADMIN, Role.ASISTENTE)
  send(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() dto: SendOrderDocumentFlowDto,
  ) {
    return this.documentFlows.send(req.user as JwtUser, id, dto);
  }
}