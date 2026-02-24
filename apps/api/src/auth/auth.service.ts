import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { PrismaService } from '../prisma/prisma.service';
import { Prisma } from '@prisma/client';
import * as bcrypt from 'bcryptjs';
import { ConfigService } from '@nestjs/config';
import { JwtUser } from './jwt-user.type';

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService
  ) {}

  async login(identifier: string, password: string) {
    const normalizedIdentifier = identifier.trim().toLowerCase();
    const user = await this.findUserForLogin(normalizedIdentifier);
    if (!user) throw new UnauthorizedException('Invalid credentials');

    const ok = await bcrypt.compare(password, user.passwordHash);
    if (!ok) throw new UnauthorizedException('Invalid credentials');

    const accessToken = await this.jwt.signAsync({
      sub: user.id,
      email: user.email,
      role: user.role,
      tokenType: 'access',
    });

    const refreshToken = await this.signRefreshToken(user.id);

    return {
      accessToken,
      refreshToken,
      user: { id: user.id, email: user.email, role: user.role },
    };
  }

  async refresh(refreshToken: string) {
    let payload: JwtUser;

    try {
      payload = await this.jwt.verifyAsync<JwtUser>(refreshToken);
    } catch {
      throw new UnauthorizedException('Invalid refresh token');
    }

    if (payload.tokenType !== 'refresh') {
      throw new UnauthorizedException('Invalid refresh token');
    }

    const user = await this.findUserForRefresh(payload.sub);
    if (!user || user.blocked === true) throw new UnauthorizedException('User blocked');

    const accessToken = await this.jwt.signAsync({
      sub: user.id,
      email: user.email,
      role: user.role,
      tokenType: 'access',
    });

    const newRefreshToken = await this.signRefreshToken(user.id);

    return {
      accessToken,
      refreshToken: newRefreshToken,
      user: { id: user.id, email: user.email, role: user.role },
    };
  }

  async me(userId: string) {
    const user = await this.findUserForMe(userId);
    if (!user) throw new UnauthorizedException('No autorizado');
    return user;
  }

  private refreshExpiresIn() {
    return this.config.get<string>('JWT_REFRESH_EXPIRES_IN') ?? '30d';
  }

  private async signRefreshToken(userId: string) {
    return this.jwt.signAsync(
      { sub: userId, tokenType: 'refresh' },
      { expiresIn: this.refreshExpiresIn() }
    );
  }

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

  private isMissingBlockedColumn(error: unknown) {
    if (error instanceof Prisma.PrismaClientKnownRequestError) {
      return error.code === 'P2022' && error.meta?.column_name === 'blocked';
    }

    if (typeof error === 'object' && error !== null) {
      const value = error as { code?: unknown; message?: unknown };
      const code = typeof value.code === 'string' ? value.code : '';
      const message = typeof value.message === 'string' ? value.message : '';
      return (
        code === 'P2022' &&
        (message.includes('blocked') ||
          (message.toLowerCase().includes('column') &&
            message.toLowerCase().includes('blocked')))
      );
    }

    return false;
  }

  private async findUserForLogin(email: string) {
    try {
      return await this.prisma.user.findUnique({
        where: { email },
        select: {
          id: true,
          email: true,
          passwordHash: true,
          role: true,
        },
      });
    } catch (error) {
      if (!this.isMissingUserTable(error)) throw error;

      const rows = await this.prisma.$queryRaw<
        Array<{ id: string; email: string; passwordHash: string; role: string }>
      >(Prisma.sql`
        SELECT id, email, "passwordHash", role
        FROM users
        WHERE email = ${email}
        LIMIT 1
      `);

      const row = rows[0];
      if (!row) return null;
      return {
        id: row.id,
        email: row.email,
        passwordHash: row.passwordHash,
        role: row.role,
      };
    }
  }

  private async findUserForMe(userId: string) {
    try {
      return await this.prisma.user.findUnique({
        where: { id: userId },
        select: {
          id: true,
          email: true,
          role: true,
        },
      });
    } catch (error) {
      if (!this.isMissingUserTable(error)) throw error;

      const rows = await this.prisma.$queryRaw<
        Array<{
          id: string;
          email: string;
          role: string;
        }>
      >(Prisma.sql`
        SELECT id, email, role
        FROM users
        WHERE id = ${userId}
        LIMIT 1
      `);

      const row = rows[0];
      if (!row) return null;
      return {
        id: row.id,
        email: row.email,
        role: row.role,
      };
    }
  }

  private async findUserForRefresh(userId: string) {
    try {
      return await this.prisma.user.findUnique({
        where: { id: userId },
        select: {
          id: true,
          email: true,
          role: true,
          blocked: true,
        },
      });
    } catch (error) {
      if (this.isMissingBlockedColumn(error)) {
        const row = await this.prisma.user.findUnique({
          where: { id: userId },
          select: { id: true, email: true, role: true },
        });
        if (!row) return null;
        return { ...row, blocked: false };
      }

      if (!this.isMissingUserTable(error)) throw error;

      const rows = await this.prisma.$queryRaw<
        Array<{
          id: string;
          email: string;
          role: string;
        }>
      >(Prisma.sql`
        SELECT id, email, role
        FROM users
        WHERE id = ${userId}
        LIMIT 1
      `);

      const row = rows[0];
      if (!row) return null;
      return {
        id: row.id,
        email: row.email,
        role: row.role as any,
        blocked: false,
      };
    }
  }
}
