/* eslint-disable no-console */

import { PrismaClient } from '@prisma/client';

type Args = {
  execute: boolean;
  confirm?: string;
  help: boolean;
};

const REQUIRED_CONFIRMATION = 'PURGE_EMPLOYEE_WARNINGS';

function parseArgs(argv: string[]): Args {
  const args: Args = {
    execute: false,
    help: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const current = argv[index];
    const next = argv[index + 1];

    if (current === '--help' || current === '-h') {
      args.help = true;
      continue;
    }

    if (current === '--execute') {
      args.execute = true;
      continue;
    }

    if (current.startsWith('--confirm=')) {
      args.confirm = current.slice('--confirm='.length).trim();
      continue;
    }

    if (current === '--confirm' && next) {
      args.confirm = next.trim();
      index += 1;
      continue;
    }

    throw new Error(`Argumento no reconocido: ${current}`);
  }

  return args;
}

function printUsage() {
  console.log(`
Uso:
  npx ts-node scripts/purge-employee-warnings.ts
  npx ts-node scripts/purge-employee-warnings.ts --execute --confirm ${REQUIRED_CONFIRMATION}

Comportamiento:
  - Sin --execute corre en DRY-RUN (solo conteos).
  - Borra TODAS las amonestaciones y su data relacionada (evidencias, firmas, auditoria).

Flags:
  --execute                Ejecuta el borrado real.
  --confirm <texto>        Debe ser exactamente ${REQUIRED_CONFIRMATION}.
  --help                   Muestra esta ayuda.
`);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (args.help) {
    printUsage();
    return;
  }

  if (args.execute && args.confirm !== REQUIRED_CONFIRMATION) {
    throw new Error(`Confirmacion invalida. Usa --confirm ${REQUIRED_CONFIRMATION}`);
  }

  const prisma = new PrismaClient();

  try {
    const [warnings, evidences, signatures, auditLogs] = await Promise.all([
      prisma.employeeWarning.count(),
      prisma.employeeWarningEvidence.count(),
      prisma.employeeWarningSignature.count(),
      prisma.employeeWarningAuditLog.count(),
    ]);

    console.log('Resumen de amonestaciones:');
    console.log(
      JSON.stringify(
        {
          mode: args.execute ? 'EXECUTE' : 'DRY_RUN',
          warnings,
          evidences,
          signatures,
          auditLogs,
        },
        null,
        2,
      ),
    );

    if (!args.execute) {
      console.log('DRY-RUN completado. No se hicieron cambios.');
      return;
    }

    const deleted = await prisma.$transaction(async (tx) => {
      const evidencesDeleted = await tx.employeeWarningEvidence.deleteMany({});
      const signaturesDeleted = await tx.employeeWarningSignature.deleteMany({});
      const auditLogsDeleted = await tx.employeeWarningAuditLog.deleteMany({});
      const warningsDeleted = await tx.employeeWarning.deleteMany({});

      return {
        warningsDeleted: warningsDeleted.count,
        evidencesDeleted: evidencesDeleted.count,
        signaturesDeleted: signaturesDeleted.count,
        auditLogsDeleted: auditLogsDeleted.count,
      };
    });

    console.log('Borrado completado:');
    console.log(JSON.stringify(deleted, null, 2));
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error) => {
  console.error('\nError en purge-employee-warnings:', error);
  process.exitCode = 1;
});
