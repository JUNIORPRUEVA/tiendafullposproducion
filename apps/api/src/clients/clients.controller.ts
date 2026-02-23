import { Body, Controller, Delete, Get, Param, Patch, Post, Query, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Request } from 'express';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { ClientsService } from './clients.service';
import { CreateClientDto } from './dto/create-client.dto';
import { ClientsQueryDto } from './dto/clients-query.dto';
import { UpdateClientDto } from './dto/update-client.dto';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR)
@Controller('clients')
export class ClientsController {
  constructor(private readonly clients: ClientsService) {}

  private ownerIdOrThrow(req: Request) {
    const user = req.user as { id?: string } | undefined;
    if (!user?.id) {
      throw new Error('Usuario no autenticado');
    }
    return user.id;
  }

  @Post()
  create(@Req() req: Request, @Body() dto: CreateClientDto) {
    return this.clients.create(this.ownerIdOrThrow(req), dto);
  }

  @Get()
  findAll(@Req() req: Request, @Query() query: ClientsQueryDto) {
    return this.clients.findAll(query);
  }

  @Get(':id')
  findOne(@Req() req: Request, @Param('id') id: string) {
    return this.clients.findOne(id);
  }

  @Patch(':id')
  update(@Req() req: Request, @Param('id') id: string, @Body() dto: UpdateClientDto) {
    return this.clients.update(id, dto);
  }

  @Delete(':id')
  remove(@Req() req: Request, @Param('id') id: string) {
    return this.clients.remove(id);
  }
}

