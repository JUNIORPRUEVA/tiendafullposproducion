const { PrismaClient } = require('@prisma/client');
const p = new PrismaClient();

async function main() {
  // Check if there's a lowercase 'products' table with categories
  const cols = await p.$queryRawUnsafe(
    "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'products' AND table_schema = 'public' ORDER BY ordinal_position"
  );
  console.log('Columnas de tabla products:', JSON.stringify(cols));

  // Check Product table
  const cols2 = await p.$queryRawUnsafe(
    "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'Product' AND table_schema = 'public' ORDER BY ordinal_position"
  );
  console.log('Columnas de tabla Product:', JSON.stringify(cols2));
}

main().finally(() => p.$disconnect());
