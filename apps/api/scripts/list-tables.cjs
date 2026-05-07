const { PrismaClient } = require('@prisma/client');
const p = new PrismaClient();

async function main() {
  const tables = await p.$queryRawUnsafe(
    "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name"
  );
  console.log('Todas las tablas:');
  tables.forEach(t => console.log(' -', t.table_name));
}

main().finally(() => p.$disconnect());
