/*
  Usage:
    - Check only:  ts-node prisma/scripts/fix_integrity.ts --check
    - Fix safe issues: ts-node prisma/scripts/fix_integrity.ts --fix

  Flags:
    --check                Only report issues (default)
    --fix                  Apply safe fixes (no deletes)
    --fix-required-nulls    Also fill required NULL fields with defaults (nombreCompleto/telefono/edad/role)
    --allow-delete          Allow deleting orphan rows (disabled by default)
*/

import { PrismaClient, Prisma, Role } from '@prisma/client';

type IntegrityReport = {
  checkedAt: string;
  totals: { totalUsers: number };
  counts: {
    requiredNulls: number;
    invalidRoles: number;
    emptyOptionalStrings: number;
    orphanUserLocations: number;
    duplicateEmails: number;
    duplicateCedulas: number;
  };
  samples: Record<string, unknown>;
};

function hasFlag(name: string) {
  return process.argv.includes(name);
}

async function buildReport(prisma: PrismaClient): Promise<IntegrityReport> {
  const checkedAt = new Date().toISOString();
  const validRoles = Object.values(Role);

  const [{ totalUsers } = { totalUsers: 0 }] = await prisma.$queryRaw<
    Array<{ totalUsers: number }>
  >(Prisma.sql`SELECT COUNT(*)::int AS "totalUsers" FROM users`);

  const [{ requiredNulls } = { requiredNulls: 0 }] = await prisma.$queryRaw<
    Array<{ requiredNulls: number }>
  >(Prisma.sql`
    SELECT COUNT(*)::int AS "requiredNulls"
    FROM users
    WHERE email IS NULL
      OR "nombreCompleto" IS NULL
      OR telefono IS NULL
      OR edad IS NULL
      OR role IS NULL
  `);

  const [{ invalidRoles } = { invalidRoles: 0 }] = await prisma.$queryRaw<
    Array<{ invalidRoles: number }>
  >(Prisma.sql`
    SELECT COUNT(*)::int AS "invalidRoles"
    FROM users
    WHERE COALESCE(role::text, '') NOT IN (${Prisma.join(validRoles)})
  `);

  const [{ emptyOptionalStrings } = { emptyOptionalStrings: 0 }] =
    await prisma.$queryRaw<Array<{ emptyOptionalStrings: number }>>(Prisma.sql`
      SELECT COUNT(*)::int AS "emptyOptionalStrings"
      FROM users
      WHERE ("telefonoFamiliar" IS NOT NULL AND TRIM("telefonoFamiliar") = '')
        OR (cedula IS NOT NULL AND TRIM(cedula) = '')
        OR ("fotoCedulaUrl" IS NOT NULL AND TRIM("fotoCedulaUrl") = '')
        OR ("fotoLicenciaUrl" IS NOT NULL AND TRIM("fotoLicenciaUrl") = '')
        OR ("fotoPersonalUrl" IS NOT NULL AND TRIM("fotoPersonalUrl") = '')
    `);

  const [{ orphanUserLocations } = { orphanUserLocations: 0 }] =
    await prisma.$queryRaw<Array<{ orphanUserLocations: number }>>(Prisma.sql`
      SELECT COUNT(*)::int AS "orphanUserLocations"
      FROM user_locations ul
      LEFT JOIN users u ON u.id = ul."userId"
      WHERE u.id IS NULL
    `);

  const duplicateEmails = await prisma.$queryRaw<
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

  const duplicateCedulas = await prisma.$queryRaw<
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

  const requiredNullSamples = await prisma.$queryRaw<any[]>(Prisma.sql`
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

  const orphanUserLocationSamples = await prisma.$queryRaw<any[]>(Prisma.sql`
    SELECT ul.id, ul."userId"
    FROM user_locations ul
    LEFT JOIN users u ON u.id = ul."userId"
    WHERE u.id IS NULL
    ORDER BY ul."updatedAt" DESC
    LIMIT 25
  `);

  return {
    checkedAt,
    totals: { totalUsers },
    counts: {
      requiredNulls,
      invalidRoles,
      emptyOptionalStrings,
      orphanUserLocations,
      duplicateEmails: duplicateEmails.length,
      duplicateCedulas: duplicateCedulas.length,
    },
    samples: {
      requiredNulls: requiredNullSamples,
      orphanUserLocations: orphanUserLocationSamples,
      duplicateEmails,
      duplicateCedulas,
    },
  };
}

async function applyFixes(prisma: PrismaClient, opts: {
  fixRequiredNulls: boolean;
  allowDelete: boolean;
}) {
  // Normalize empty strings to NULL for optional columns.
  await prisma.$executeRaw(Prisma.sql`
    UPDATE users
    SET "telefonoFamiliar" = NULL
    WHERE "telefonoFamiliar" IS NOT NULL AND TRIM("telefonoFamiliar") = ''
  `);
  await prisma.$executeRaw(Prisma.sql`
    UPDATE users
    SET cedula = NULL
    WHERE cedula IS NOT NULL AND TRIM(cedula) = ''
  `);
  await prisma.$executeRaw(Prisma.sql`
    UPDATE users
    SET "fotoCedulaUrl" = NULL
    WHERE "fotoCedulaUrl" IS NOT NULL AND TRIM("fotoCedulaUrl") = ''
  `);
  await prisma.$executeRaw(Prisma.sql`
    UPDATE users
    SET "fotoLicenciaUrl" = NULL
    WHERE "fotoLicenciaUrl" IS NOT NULL AND TRIM("fotoLicenciaUrl") = ''
  `);
  await prisma.$executeRaw(Prisma.sql`
    UPDATE users
    SET "fotoPersonalUrl" = NULL
    WHERE "fotoPersonalUrl" IS NOT NULL AND TRIM("fotoPersonalUrl") = ''
  `);

  // Optional: fill required NULL fields with safe defaults.
  if (opts.fixRequiredNulls) {
    await prisma.$executeRaw(Prisma.sql`
      UPDATE users
      SET "nombreCompleto" = ''
      WHERE "nombreCompleto" IS NULL
    `);
    await prisma.$executeRaw(Prisma.sql`
      UPDATE users
      SET telefono = ''
      WHERE telefono IS NULL
    `);
    await prisma.$executeRaw(Prisma.sql`
      UPDATE users
      SET edad = 0
      WHERE edad IS NULL
    `);
    await prisma.$executeRaw(Prisma.sql`
      UPDATE users
      SET role = 'ASISTENTE'
      WHERE role IS NULL
    `);
  }

  // Orphans: never delete unless explicitly enabled.
  if (opts.allowDelete) {
    await prisma.$executeRaw(Prisma.sql`
      DELETE FROM user_locations ul
      WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.id = ul."userId")
    `);
  }
}

async function main() {
  const check = hasFlag('--check') || (!hasFlag('--fix') && !hasFlag('--fix-required-nulls'));
  const fix = hasFlag('--fix');
  const fixRequiredNulls = hasFlag('--fix-required-nulls');
  const allowDelete = hasFlag('--allow-delete');

  const prisma = new PrismaClient();
  try {
    if (fix) {
      await applyFixes(prisma, { fixRequiredNulls, allowDelete });
    }

    const report = await buildReport(prisma);
    // eslint-disable-next-line no-console
    console.log(JSON.stringify(report, null, 2));

    const hasIssues =
      report.counts.requiredNulls > 0 ||
      report.counts.invalidRoles > 0 ||
      report.counts.emptyOptionalStrings > 0 ||
      report.counts.orphanUserLocations > 0 ||
      report.counts.duplicateEmails > 0 ||
      report.counts.duplicateCedulas > 0;

    if (check && hasIssues) {
      process.exitCode = 2;
    }
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((e) => {
  // eslint-disable-next-line no-console
  console.error(e);
  process.exitCode = 1;
});
