import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { Prisma } from '@prisma/client';
import { CreateUserDto } from './dto/create-user.dto';
import { UpdateUserDto } from './dto/update-user.dto';
import * as bcrypt from 'bcryptjs';
import { SelfUpdateUserDto } from './dto/self-update-user.dto';

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  private isMissingUserTable(error: unknown) {
    if (error instanceof Prisma.PrismaClientKnownRequestError) {
      return error.code === 'P2021';
    }

    if (typeof error === 'object' && error !== null) {
      const value = error as { code?: unknown; message?: unknown };
      const code = typeof value.code === 'string' ? value.code : '';
      const message = typeof value.message === 'string' ? value.message : '';
      return code === 'P2021' || message.includes('does not exist in the current database');
    }

    return false;
  }

  private mapMinimalUser(row: {
    id: string;
    email: string;
    role: string;
    createdAt: Date;
    updatedAt: Date;
  }) {
    return {
      id: row.id,
      email: row.email,
      nombreCompleto: '',
      telefono: '',
      telefonoFamiliar: null,
      cedula: null,
      fotoCedulaUrl: null,
      fotoLicenciaUrl: null,
      fotoPersonalUrl: null,
      edad: null,
      tieneHijos: false,
      estaCasado: false,
      casaPropia: false,
      vehiculo: false,
      licenciaConducir: false,
      role: row.role,
      blocked: false,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    };
  }

  async findById(id: string) {
    let user: any;

    try {
      user = await this.prisma.user.findUnique({
        where: { id },
        select: {
          id: true,
          email: true,
          nombreCompleto: true,
          telefono: true,
          telefonoFamiliar: true,
          cedula: true,
          fotoCedulaUrl: true,
          fotoLicenciaUrl: true,
          fotoPersonalUrl: true,
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
    } catch (error) {
      if (!this.isMissingUserTable(error)) throw error;

      const rows = await this.prisma.$queryRaw<
        Array<{ id: string; email: string; role: string; createdAt: Date; updatedAt: Date }>
      >(Prisma.sql`
        SELECT id, email, role, "createdAt", "updatedAt"
        FROM users
        WHERE id::text = ${id}
        LIMIT 1
      `);

      user = rows[0] ? this.mapMinimalUser(rows[0]) : null;
    }

    if (!user) throw new NotFoundException('User not found');
    return user;
  }

  async create(dto: CreateUserDto) {
    const exists = await this.prisma.user.findUnique({ where: { email: dto.email } });
    if (exists) throw new BadRequestException('Email already in use');

    if (dto.cedula) {
      const cedulaTaken = await this.prisma.user.findUnique({ where: { cedula: dto.cedula } });
      if (cedulaTaken) throw new BadRequestException('La cédula ya está registrada');
    }

    const passwordHash = await bcrypt.hash(dto.password, 10);
    return this.prisma.user.create({
      data: {
        email: dto.email,
        passwordHash,
        nombreCompleto: dto.nombreCompleto,
        telefono: dto.telefono,
        telefonoFamiliar: dto.telefonoFamiliar,
        cedula: dto.cedula,
        fotoCedulaUrl: dto.fotoCedulaUrl,
        fotoLicenciaUrl: dto.fotoLicenciaUrl,
        fotoPersonalUrl: dto.fotoPersonalUrl,
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
        telefonoFamiliar: true,
        cedula: true,
        fotoCedulaUrl: true,
        fotoLicenciaUrl: true,
        fotoPersonalUrl: true,
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
        telefonoFamiliar: true,
        cedula: true,
        fotoCedulaUrl: true,
        fotoLicenciaUrl: true,
        fotoPersonalUrl: true,
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
    }).catch(async (error) => {
      if (!this.isMissingUserTable(error)) throw error;
      const rows = await this.prisma.$queryRaw<
        Array<{ id: string; email: string; role: string; createdAt: Date; updatedAt: Date }>
      >(Prisma.sql`
        SELECT id, email, role, "createdAt", "updatedAt"
        FROM users
        ORDER BY "createdAt" DESC
      `);
      return rows.map((row) => this.mapMinimalUser(row));
    });
  }

  async update(id: string, dto: UpdateUserDto) {
    const existing = await this.prisma.user.findUnique({ where: { id } });
    if (!existing) throw new NotFoundException('User not found');

    if (dto.email && dto.email !== existing.email) {
      const emailTaken = await this.prisma.user.findUnique({ where: { email: dto.email } });
      if (emailTaken) throw new BadRequestException('Email already in use');
    }

    if (dto.cedula && dto.cedula !== existing.cedula) {
      const cedulaTaken = await this.prisma.user.findUnique({ where: { cedula: dto.cedula } });
      if (cedulaTaken) throw new BadRequestException('La cédula ya está registrada');
    }

    const passwordHash = dto.password ? await bcrypt.hash(dto.password, 10) : undefined;
    return this.prisma.user.update({
      where: { id },
      data: {
        email: dto.email,
        passwordHash,
        nombreCompleto: dto.nombreCompleto,
        telefono: dto.telefono,
        telefonoFamiliar: dto.telefonoFamiliar,
        cedula: dto.cedula,
        fotoCedulaUrl: dto.fotoCedulaUrl,
        fotoLicenciaUrl: dto.fotoLicenciaUrl,
        fotoPersonalUrl: dto.fotoPersonalUrl,
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
        telefonoFamiliar: true,
        cedula: true,
        fotoCedulaUrl: true,
        fotoLicenciaUrl: true,
        fotoPersonalUrl: true,
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

  async updateSelf(id: string, dto: SelfUpdateUserDto) {
    const existing = await this.prisma.user.findUnique({ where: { id } });
    if (!existing) throw new NotFoundException('User not found');

    if (dto.email && dto.email !== existing.email) {
      const emailTaken = await this.prisma.user.findUnique({ where: { email: dto.email } });
      if (emailTaken) throw new BadRequestException('Email already in use');
    }

    const passwordHash = dto.password ? await bcrypt.hash(dto.password, 10) : undefined;
    return this.prisma.user.update({
      where: { id },
      data: {
        email: dto.email,
        nombreCompleto: dto.nombreCompleto,
        telefono: dto.telefono,
        passwordHash
      },
      select: {
        id: true,
        email: true,
        nombreCompleto: true,
        telefono: true,
        telefonoFamiliar: true,
        cedula: true,
        fotoCedulaUrl: true,
        fotoLicenciaUrl: true,
        fotoPersonalUrl: true,
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
