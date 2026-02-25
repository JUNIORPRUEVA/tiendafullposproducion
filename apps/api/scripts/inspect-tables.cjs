const { PrismaClient } = require('@prisma/client');

const prisma = new PrismaClient();

async function main() {
  const tables = await prisma.$queryRawUnsafe(
    "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name"
  );

  const grouped = new Map();
  for (const row of tables) {
    const tableName = row.table_name;
    const key = tableName.toLowerCase();
    if (!grouped.has(key)) grouped.set(key, []);
    grouped.get(key).push(tableName);
  }

  console.log('TABLES:');
  console.table(tables);

  const duplicates = [...grouped.entries()]
    .filter(([, names]) => names.length > 1)
    .map(([key, names]) => ({ key, names: names.join(', ') }));

  console.log('POSSIBLE CASE-DUPLICATES:');
  console.table(duplicates);
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
