import { ForbiddenException, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { PrismaService } from '../prisma/prisma.service';
import * as bcrypt from 'bcryptjs';

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService
  ) {}

  async login(email: string, password: string) {
    const user = await this.prisma.user.findUnique({ where: { email } });
    if (!user) throw new UnauthorizedException('Invalid credentials');
    if (user.blocked) throw new ForbiddenException('User blocked');

    const ok = await bcrypt.compare(password, user.passwordHash);
    if (!ok) throw new UnauthorizedException('Invalid credentials');

    const accessToken = await this.jwt.signAsync({
      sub: user.id,
      email: user.email,
      role: user.role
    });

    return { accessToken };
  }

  async me(userId: string) {
    return this.prisma.user.findUnique({
      where: { id: userId },
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
}

