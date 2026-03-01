import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { Prisma } from '@prisma/client';
import { CreateUserDto } from './dto/create-user.dto';
import { UpdateUserDto } from './dto/update-user.dto';
import * as bcrypt from 'bcryptjs';
import { SelfUpdateUserDto } from './dto/self-update-user.dto';
import { ConfigService } from '@nestjs/config';

@Injectable()
export class UsersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService
  ) {}

  private async getOpenAiRuntimeConfig() {
    const envKey = (this.config.get<string>('OPENAI_API_KEY') ?? process.env.OPENAI_API_KEY ?? '').trim();
    const envModel = (this.config.get<string>('OPENAI_MODEL') ?? process.env.OPENAI_MODEL ?? '').trim();

    let appConfig: { openAiApiKey: string | null; openAiModel: string | null; companyName: string | null } | null = null;
    try {
      appConfig = await this.prisma.appConfig.findUnique({
        where: { id: 'global' },
        select: { openAiApiKey: true, openAiModel: true, companyName: true }
      });
    } catch {
      // ignore missing table/rows, fallback to env vars only
    }

    const apiKey = envKey.length > 0 ? envKey : (appConfig?.openAiApiKey ?? '').trim();
    const model = envModel.length > 0
      ? envModel
      : ((appConfig?.openAiModel ?? '').trim() || 'gpt-4o-mini');
    const companyName = (appConfig?.companyName ?? '').trim();
    return { apiKey, model, companyName };
  }

  private isBirthdayToday(birthDate: Date) {
    const now = new Date();
    return now.getMonth() === birthDate.getMonth() && now.getDate() === birthDate.getDate();
  }

  async generateBirthdayGreeting(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, nombreCompleto: true, fechaNacimiento: true }
    });
    if (!user) throw new NotFoundException('User not found');

    if (!user.fechaNacimiento) {
      return {
        userId: user.id,
        isBirthdayToday: false,
        birthdayKnown: false,
        message: 'No hay fecha de nacimiento registrada para este usuario.'
      };
    }

    const isToday = this.isBirthdayToday(user.fechaNacimiento);
    const birthdayFmt = user.fechaNacimiento.toISOString().slice(0, 10);
    if (!isToday) {
      return {
        userId: user.id,
        isBirthdayToday: false,
        birthdayKnown: true,
        birthday: birthdayFmt,
        message: 'Hoy no es su cumpleaños.'
      };
    }

    const { apiKey, model, companyName } = await this.getOpenAiRuntimeConfig();
    const employeeName = (user.nombreCompleto ?? '').trim() || 'nuestro colaborador';

    if (!apiKey) {
      const from = companyName.length > 0 ? companyName : 'el equipo';
      return {
        userId: user.id,
        isBirthdayToday: true,
        birthdayKnown: true,
        birthday: birthdayFmt,
        source: 'template',
        message: `Feliz cumpleaños, ${employeeName}. ¡Te deseamos un día excelente! — ${from}`
      };
    }

    const prompt = `Genera un mensaje corto (1-2 frases), profesional y cálido en español para felicitar el cumpleaños de un empleado.
Empleado: ${employeeName}
Empresa: ${companyName || 'FULLTECH'}
Requisitos: sin emojis, sin chistes, no menciones IA, no uses información no proporcionada.`;

    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model,
        messages: [
          { role: 'system', content: 'Eres un asistente que redacta mensajes corporativos breves.' },
          { role: 'user', content: prompt },
        ],
        temperature: 0.7,
      }),
    });

    if (!response.ok) {
      const from = companyName.length > 0 ? companyName : 'el equipo';
      return {
        userId: user.id,
        isBirthdayToday: true,
        birthdayKnown: true,
        birthday: birthdayFmt,
        source: 'template',
        message: `Feliz cumpleaños, ${employeeName}. ¡Te deseamos un día excelente! — ${from}`,
      };
    }

    const data = (await response.json()) as any;
    const content = (data?.choices?.[0]?.message?.content ?? '').toString().trim();

    return {
      userId: user.id,
      isBirthdayToday: true,
      birthdayKnown: true,
      birthday: birthdayFmt,
      source: 'openai',
      message: content.length > 0 ? content : `Feliz cumpleaños, ${employeeName}.`,
    };
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

  private isInconsistentQueryResult(error: unknown) {
    if (typeof error !== 'object' || error === null) return false;
    const value = error as { message?: unknown; name?: unknown };
    const message = typeof value.message === 'string' ? value.message : '';
    const name = typeof value.name === 'string' ? value.name : '';
    return (
      message.includes('Inconsistent query result') ||
      message.includes('got null instead') ||
      name.includes('PrismaClientUnknownRequestError')
    );
  }

  private mapSafeUserRow(row: any) {
    return {
      id: row.id,
      email: row.email,
      nombreCompleto: row.nombreCompleto ?? '',
      telefono: row.telefono ?? '',
      telefonoFamiliar: row.telefonoFamiliar ?? null,
      cedula: row.cedula ?? null,
      fotoCedulaUrl: row.fotoCedulaUrl ?? null,
      fotoLicenciaUrl: row.fotoLicenciaUrl ?? null,
      fotoPersonalUrl: row.fotoPersonalUrl ?? null,
      edad: row.edad ?? 0,
      tieneHijos: row.tieneHijos ?? false,
      estaCasado: row.estaCasado ?? false,
      casaPropia: row.casaPropia ?? false,
      vehiculo: row.vehiculo ?? false,
      licenciaConducir: row.licenciaConducir ?? false,
      fechaIngreso: row.fechaIngreso ?? null,
      fechaNacimiento: row.fechaNacimiento ?? null,
      cuentaNominaPreferencial: row.cuentaNominaPreferencial ?? null,
      habilidades: row.habilidades ?? null,
      role: row.role ?? 'ASISTENTE',
      blocked: row.blocked ?? false,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    };
  }

  private async findAllSafe() {
    const rows = await this.prisma.$queryRaw<any[]>(Prisma.sql`
      SELECT
        id,
        email,
        COALESCE("nombreCompleto", '') AS "nombreCompleto",
        COALESCE(telefono, '') AS telefono,
        "telefonoFamiliar",
        cedula,
        "fotoCedulaUrl",
        "fotoLicenciaUrl",
        "fotoPersonalUrl",
        COALESCE(edad, 0) AS edad,
        COALESCE("tieneHijos", false) AS "tieneHijos",
        COALESCE("estaCasado", false) AS "estaCasado",
        COALESCE("casaPropia", false) AS "casaPropia",
        COALESCE(vehiculo, false) AS vehiculo,
        COALESCE("licenciaConducir", false) AS "licenciaConducir",
        "fechaIngreso",
        "fechaNacimiento",
        "cuentaNominaPreferencial",
        habilidades,
        COALESCE(role::text, 'ASISTENTE') AS role,
        COALESCE(blocked, false) AS blocked,
        "createdAt",
        "updatedAt"
      FROM users
      ORDER BY "createdAt" DESC
    `);

    return rows.map((row) => this.mapSafeUserRow(row));
  }

  private async findByIdSafe(id: string) {
    const rows = await this.prisma.$queryRaw<any[]>(Prisma.sql`
      SELECT
        id,
        email,
        COALESCE("nombreCompleto", '') AS "nombreCompleto",
        COALESCE(telefono, '') AS telefono,
        "telefonoFamiliar",
        cedula,
        "fotoCedulaUrl",
        "fotoLicenciaUrl",
        "fotoPersonalUrl",
        COALESCE(edad, 0) AS edad,
        COALESCE("tieneHijos", false) AS "tieneHijos",
        COALESCE("estaCasado", false) AS "estaCasado",
        COALESCE("casaPropia", false) AS "casaPropia",
        COALESCE(vehiculo, false) AS vehiculo,
        COALESCE("licenciaConducir", false) AS "licenciaConducir",
        "fechaIngreso",
        "fechaNacimiento",
        "cuentaNominaPreferencial",
        habilidades,
        COALESCE(role::text, 'ASISTENTE') AS role,
        COALESCE(blocked, false) AS blocked,
        "createdAt",
        "updatedAt"
      FROM users
      WHERE id::text = ${id}
      LIMIT 1
    `);

    const row = rows[0];
    if (!row) throw new NotFoundException('User not found');
    return this.mapSafeUserRow(row);
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
      fechaIngreso: null,
      fechaNacimiento: null,
      cuentaNominaPreferencial: null,
      habilidades: null,
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
          fechaIngreso: true,
          fechaNacimiento: true,
          cuentaNominaPreferencial: true,
          habilidades: true,
          role: true,
          blocked: true,
          createdAt: true,
          updatedAt: true
        }
      });
    } catch (error) {
      if (this.isInconsistentQueryResult(error)) {
        return this.findByIdSafe(id);
      }
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
        fechaIngreso: dto.fechaIngreso ? new Date(dto.fechaIngreso) : undefined,
        fechaNacimiento: dto.fechaNacimiento ? new Date(dto.fechaNacimiento) : undefined,
        cuentaNominaPreferencial: dto.cuentaNominaPreferencial,
        habilidades: dto.habilidades,
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
        fechaIngreso: true,
        fechaNacimiento: true,
        cuentaNominaPreferencial: true,
        habilidades: true,
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
        fechaIngreso: true,
        fechaNacimiento: true,
        cuentaNominaPreferencial: true,
        habilidades: true,
        role: true,
        blocked: true,
        createdAt: true,
        updatedAt: true
      }
    }).catch(async (error) => {
      if (this.isInconsistentQueryResult(error)) {
        return this.findAllSafe();
      }

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
    await this.prisma.user.update({
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
        fechaIngreso: dto.fechaIngreso ? new Date(dto.fechaIngreso) : undefined,
        fechaNacimiento: dto.fechaNacimiento ? new Date(dto.fechaNacimiento) : undefined,
        cuentaNominaPreferencial: dto.cuentaNominaPreferencial,
        habilidades: dto.habilidades,
        role: dto.role,
        blocked: dto.blocked
      },
      select: { id: true }
    });

    return this.findById(id);
  }

  async updateSelf(id: string, dto: SelfUpdateUserDto) {
    const existing = await this.prisma.user.findUnique({ where: { id } });
    if (!existing) throw new NotFoundException('User not found');

    if (dto.email && dto.email !== existing.email) {
      const emailTaken = await this.prisma.user.findUnique({ where: { email: dto.email } });
      if (emailTaken) throw new BadRequestException('Email already in use');
    }

    const passwordHash = dto.password ? await bcrypt.hash(dto.password, 10) : undefined;

    const data: Prisma.UserUpdateInput = {};
    const email = (dto as any).email === null ? undefined : dto.email;
    const nombreCompleto = (dto as any).nombreCompleto === null ? undefined : dto.nombreCompleto;
    const telefono = (dto as any).telefono === null ? undefined : dto.telefono;
    const fotoPersonalUrl = (dto as any).fotoPersonalUrl === null ? undefined : dto.fotoPersonalUrl;
    const password = (dto as any).password === null ? undefined : dto.password;

    if (email !== undefined) data.email = email;
    if (nombreCompleto !== undefined) data.nombreCompleto = nombreCompleto;
    if (telefono !== undefined) data.telefono = telefono;
    if (fotoPersonalUrl !== undefined) data.fotoPersonalUrl = fotoPersonalUrl;
    if (password !== undefined && passwordHash !== undefined) data.passwordHash = passwordHash;

    if (Object.keys(data).length === 0) {
      return this.findById(id);
    }

    await this.prisma.user.update({
      where: { id },
      data,
      select: { id: true }
    });

    return this.findById(id);
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
