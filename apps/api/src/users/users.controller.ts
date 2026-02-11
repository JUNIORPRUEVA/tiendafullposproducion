import { Body, Controller, Delete, Get, Param, Patch, Post, Req, UseGuards } from '@nestjs/common';
import { UsersService } from './users.service';
import { AuthGuard } from '@nestjs/passport';
import { Roles } from '../auth/roles.decorator';
import { Role } from '@prisma/client';
import { RolesGuard } from '../auth/roles.guard';
import { CreateUserDto } from './dto/create-user.dto';
import { UpdateUserDto } from './dto/update-user.dto';
import { BlockUserDto } from './dto/block-user.dto';
import { SelfUpdateUserDto } from './dto/self-update-user.dto';
import { Request } from 'express';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('users')
export class UsersController {
  constructor(private readonly users: UsersService) {}

  @Post()
  @Roles(Role.ADMIN)
  create(@Body() dto: CreateUserDto) {
    return this.users.create(dto);
  }

  @Get()
  @Roles(Role.ADMIN)
  findAll() {
    return this.users.findAll();
  }

  @Patch(':id')
  @Roles(Role.ADMIN)
  update(@Param('id') id: string, @Body() dto: UpdateUserDto) {
    return this.users.update(id, dto);
  }

  @Patch(':id/block')
  @Roles(Role.ADMIN)
  setBlocked(@Param('id') id: string, @Body() dto: BlockUserDto) {
    return this.users.setBlocked(id, dto.blocked);
  }

  @Delete(':id')
  @Roles(Role.ADMIN)
  remove(@Param('id') id: string) {
    return this.users.remove(id);
  }

  @Get('me')
  me(@Req() req: Request) {
    const user = req.user as { id?: string } | undefined;
    if (!user?.id) {
      throw new Error('Usuario no autenticado');
    }
    return this.users.findById(user.id);
  }

  @Patch('me')
  updateSelf(@Req() req: Request, @Body() dto: SelfUpdateUserDto) {
    const user = req.user as { id?: string } | undefined;
    if (!user?.id) {
      throw new Error('Usuario no autenticado');
    }
    return this.users.updateSelf(user.id, dto);
  }
}

