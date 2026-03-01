import { Injectable } from '@nestjs/common';
import { Prisma, Role } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

type SampleRow = Record<string, unknown>;

@Injectable()
export class AdminDiagnosticsService {
  constructor(private readonly prisma: PrismaService) {}

  private readonly validRoles = Object.values(Role);

  async usersIntegrityReport() {
    const checkedAt = new Date().toISOString();

    const [{ totalUsers } = { totalUsers: 0 }] = await this.prisma.$queryRaw<
      Array<{ totalUsers: number }>
    >(Prisma.sql`
      SELECT COUNT(*)::int AS "totalUsers" FROM users
    `);

    const requiredNulls = await this.prisma.$queryRaw<SampleRow[]>(Prisma.sql`
      SELECT id, email,
        (email IS NULL) AS "emailIsNull",
        ("nombreCompleto" IS NULL) AS "nombreCompletoIsNull",
        (telefono IS NULL) AS "telefonoIsNull",
        (edad IS NULL) AS "edadIsNull",
        (role IS NULL) AS "roleIsNull"
      FROM users
      WHERE email IS NULL
        OR "nombreCompleto" IS NULL
        OR telefono IS NULL
        OR edad IS NULL
        OR role IS NULL
      ORDER BY "createdAt" DESC
      LIMIT 25
    `);

    const invalidRoles = await this.prisma.$queryRaw<SampleRow[]>(Prisma.sql`
      SELECT id, email, COALESCE(role::text, '') AS role
      FROM users
      WHERE COALESCE(role::text, '') NOT IN (${Prisma.join(this.validRoles)})
      ORDER BY "createdAt" DESC
      LIMIT 25
    `);

    const duplicateEmails = await this.prisma.$queryRaw<
      Array<{ email: string; count: number }>
    >(Prisma.sql`
      SELECT LOWER(email) AS email, COUNT(*)::int AS count
      FROM users
      WHERE email IS NOT NULL
      GROUP BY LOWER(email)
      HAVING COUNT(*) > 1
      ORDER BY COUNT(*) DESC
      LIMIT 25
    `);

    const duplicateCedulas = await this.prisma.$queryRaw<
      Array<{ cedula: string; count: number }>
    >(Prisma.sql`
      SELECT cedula, COUNT(*)::int AS count
      FROM users
      WHERE cedula IS NOT NULL AND TRIM(cedula) <> ''
      GROUP BY cedula
      HAVING COUNT(*) > 1
      ORDER BY COUNT(*) DESC
      LIMIT 25
    `);

    const emptyOptionalStrings = await this.prisma.$queryRaw<SampleRow[]>(Prisma.sql`
      SELECT id, email,
        (telefono IS NOT NULL AND TRIM(telefono) = '') AS "telefonoEmpty",
        ("telefonoFamiliar" IS NOT NULL AND TRIM("telefonoFamiliar") = '') AS "telefonoFamiliarEmpty",
        (cedula IS NOT NULL AND TRIM(cedula) = '') AS "cedulaEmpty",
        ("fotoCedulaUrl" IS NOT NULL AND TRIM("fotoCedulaUrl") = '') AS "fotoCedulaUrlEmpty",
        ("fotoLicenciaUrl" IS NOT NULL AND TRIM("fotoLicenciaUrl") = '') AS "fotoLicenciaUrlEmpty",
        ("fotoPersonalUrl" IS NOT NULL AND TRIM("fotoPersonalUrl") = '') AS "fotoPersonalUrlEmpty"
      FROM users
      WHERE ("telefonoFamiliar" IS NOT NULL AND TRIM("telefonoFamiliar") = '')
        OR (cedula IS NOT NULL AND TRIM(cedula) = '')
        OR ("fotoCedulaUrl" IS NOT NULL AND TRIM("fotoCedulaUrl") = '')
        OR ("fotoLicenciaUrl" IS NOT NULL AND TRIM("fotoLicenciaUrl") = '')
        OR ("fotoPersonalUrl" IS NOT NULL AND TRIM("fotoPersonalUrl") = '')
      ORDER BY "createdAt" DESC
      LIMIT 25
    `);

    const orphanUserLocations = await this.prisma.$queryRaw<SampleRow[]>(Prisma.sql`
      SELECT ul.id, ul."userId"
      FROM user_locations ul
      LEFT JOIN users u ON u.id = ul."userId"
      WHERE u.id IS NULL
      ORDER BY ul."updatedAt" DESC
      LIMIT 25
    `);

    // Counts (fast, for dashboards)
    const [{ requiredNullsCount } = { requiredNullsCount: 0 }] =
      await this.prisma.$queryRaw<Array<{ requiredNullsCount: number }>>(Prisma.sql`
        SELECT COUNT(*)::int AS "requiredNullsCount"
        FROM users
        WHERE email IS NULL
          OR "nombreCompleto" IS NULL
          OR telefono IS NULL
          OR edad IS NULL
          OR role IS NULL
      `);

    const [{ invalidRolesCount } = { invalidRolesCount: 0 }] =
      await this.prisma.$queryRaw<Array<{ invalidRolesCount: number }>>(Prisma.sql`
        SELECT COUNT(*)::int AS "invalidRolesCount"
        FROM users
        WHERE COALESCE(role::text, '') NOT IN (${Prisma.join(this.validRoles)})
      `);

    const [{ emptyOptionalStringsCount } = { emptyOptionalStringsCount: 0 }] =
      await this.prisma.$queryRaw<Array<{ emptyOptionalStringsCount: number }>>(
        Prisma.sql`
          SELECT COUNT(*)::int AS "emptyOptionalStringsCount"
          FROM users
          WHERE ("telefonoFamiliar" IS NOT NULL AND TRIM("telefonoFamiliar") = '')
            OR (cedula IS NOT NULL AND TRIM(cedula) = '')
            OR ("fotoCedulaUrl" IS NOT NULL AND TRIM("fotoCedulaUrl") = '')
            OR ("fotoLicenciaUrl" IS NOT NULL AND TRIM("fotoLicenciaUrl") = '')
            OR ("fotoPersonalUrl" IS NOT NULL AND TRIM("fotoPersonalUrl") = '')
        `,
      );

    const [{ orphanUserLocationsCount } = { orphanUserLocationsCount: 0 }] =
      await this.prisma.$queryRaw<Array<{ orphanUserLocationsCount: number }>>(
        Prisma.sql`
          SELECT COUNT(*)::int AS "orphanUserLocationsCount"
          FROM user_locations ul
          LEFT JOIN users u ON u.id = ul."userId"
          WHERE u.id IS NULL
        `,
      );

    return {
      checkedAt,
      totals: {
        totalUsers,
      },
      counts: {
        requiredNulls: requiredNullsCount,
        invalidRoles: invalidRolesCount,
        emptyOptionalStrings: emptyOptionalStringsCount,
        orphanUserLocations: orphanUserLocationsCount,
        duplicateEmails: duplicateEmails.length,
        duplicateCedulas: duplicateCedulas.length,
      },
      samples: {
        requiredNulls,
        invalidRoles,
        emptyOptionalStrings,
        orphanUserLocations,
        duplicateEmails,
        duplicateCedulas,
      },
    };
  }
}
