import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateUserDto } from './dto/create-user.dto';
import { UpdateUserDto } from './dto/update-user.dto';
import * as bcrypt from 'bcryptjs';

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  async create(dto: CreateUserDto) {
    const exists = await this.prisma.user.findUnique({ where: { email: dto.email } });
    if (exists) throw new BadRequestException('Email already in use');

    const passwordHash = await bcrypt.hash(dto.password, 10);
    return this.prisma.user.create({
      data: {
        email: dto.email,
        passwordHash,
        nombreCompleto: dto.nombreCompleto,
        telefono: dto.telefono,
        edad: dto.edad,
        tieneHijos: dto.tieneHijos ?? false,
        estaCasado: dto.estaCasado ?? false,
        casaPropia: dto.casaPropia ?? false,
        vehiculo: dto.vehiculo ?? false,
        licenciaConducir: dto.licenciaConducir ?? false,
        role: dto.role,
        blocked: dto.blocked ?? false
      },
      select: {
        id: true,
        email: true,
        nombreCompleto: true,
        telefono: true,
        edad: true,
        tieneHijos: true,
        estaCasado: true,
        casaPropia: true,
        vehiculo: true,
        licenciaConducir: true,
        role: true,
        blocked: true,
        createdAt: true,
        updatedAt: true
      }
    });
  }

  findAll() {
    return this.prisma.user.findMany({
      orderBy: { createdAt: 'desc' },
      select: {
        id: true,
        email: true,
        nombreCompleto: true,
        telefono: true,
        edad: true,
        tieneHijos: true,
        estaCasado: true,
        casaPropia: true,
        vehiculo: true,
        licenciaConducir: true,
        role: true,
        blocked: true,
        createdAt: true,
        updatedAt: true
      }
    });
  }

  async update(id: string, dto: UpdateUserDto) {
    const existing = await this.prisma.user.findUnique({ where: { id } });
    if (!existing) throw new NotFoundException('User not found');

    const passwordHash = dto.password ? await bcrypt.hash(dto.password, 10) : undefined;
    return this.prisma.user.update({
      where: { id },
      data: {
        passwordHash,
        nombreCompleto: dto.nombreCompleto,
        telefono: dto.telefono,
        edad: dto.edad,
        tieneHijos: dto.tieneHijos,
        estaCasado: dto.estaCasado,
        casaPropia: dto.casaPropia,
        vehiculo: dto.vehiculo,
        licenciaConducir: dto.licenciaConducir,
        role: dto.role,
        blocked: dto.blocked
      },
      select: {
        id: true,
        email: true,
        nombreCompleto: true,
        telefono: true,
        edad: true,
        tieneHijos: true,
        estaCasado: true,
        casaPropia: true,
        vehiculo: true,
        licenciaConducir: true,
        role: true,
        blocked: true,
        createdAt: true,
        updatedAt: true
      }
    });
  }

  async setBlocked(id: string, blocked?: boolean) {
    const existing = await this.prisma.user.findUnique({ where: { id } });
    if (!existing) throw new NotFoundException('User not found');
    const next = blocked ?? !existing.blocked;

    return this.prisma.user.update({
      where: { id },
      data: { blocked: next },
      select: {
        id: true,
        email: true,
        role: true,
        blocked: true,
        updatedAt: true
      }
    });
  }

  async remove(id: string) {
    const existing = await this.prisma.user.findUnique({ where: { id } });
    if (!existing) throw new NotFoundException('User not found');
    await this.prisma.user.delete({ where: { id } });
    return { ok: true };
  }
}
