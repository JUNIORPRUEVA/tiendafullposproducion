#!/usr/bin/env node

const { PrismaClient } = require('@prisma/client');

async function main() {
  const prisma = new PrismaClient();
  try {
    const tables = await prisma.$queryRawUnsafe(`
      SELECT table_name
      FROM information_schema.tables
      WHERE table_schema = 'public'
        AND table_name IN ('User', 'users')
      ORDER BY table_name;
    `);

    console.log('Tables named User/users in public schema:');
    console.dir(tables, { depth: null });

    const fkRefs = await prisma.$queryRawUnsafe(`
      SELECT
        con.conname AS constraint_name,
        src.relname AS source_table,
        tgt.relname AS target_table,
        pg_get_constraintdef(con.oid) AS definition
      FROM pg_constraint con
      JOIN pg_class src ON src.oid = con.conrelid
      JOIN pg_class tgt ON tgt.oid = con.confrelid
      WHERE con.contype = 'f'
        AND tgt.relname IN ('User', 'users')
      ORDER BY target_table, source_table, constraint_name;
    `);

    console.log('\nForeign keys referencing User/users:');
    console.dir(fkRefs, { depth: null });
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
