#!/usr/bin/env node

const { PrismaClient } = require('@prisma/client');

async function main() {
  const migrationName = process.argv[2];
  if (!migrationName) {
    console.error('Usage: node scripts/print-prisma-migration-log.cjs <migration_name>');
    process.exit(1);
  }

  const prisma = new PrismaClient();
  try {
    const rows = await prisma.$queryRawUnsafe(
      `SELECT migration_name, started_at, finished_at, rolled_back_at, applied_steps_count, logs\n` +
        `FROM _prisma_migrations\n` +
        `WHERE migration_name = '${migrationName.replace(/'/g, "''")}';`,
    );

    if (!rows || rows.length === 0) {
      console.log('No rows found in _prisma_migrations for:', migrationName);
      return;
    }

    for (const row of rows) {
      console.log('---');
      console.log('migration_name:', row.migration_name);
      console.log('started_at:', row.started_at);
      console.log('finished_at:', row.finished_at);
      console.log('rolled_back_at:', row.rolled_back_at);
      console.log('applied_steps_count:', row.applied_steps_count);
      console.log('logs:\n' + (row.logs ?? ''));
    }
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
