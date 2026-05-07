const { PrismaClient } = require('@prisma/client');
const p = new PrismaClient();

async function main() {
  // Check raw table name by querying information_schema
  const tables = await p.$queryRaw`
    SELECT table_name FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_name ILIKE '%product%'
    ORDER BY table_name
  `;
  console.log('Tablas product-related:', JSON.stringify(tables, null, 2));

  // Check all distinct categories
  const cats = await p.$queryRaw`
    SELECT DISTINCT categoria, COUNT(*) as total
    FROM "Product"
    GROUP BY categoria
    ORDER BY total DESC
    LIMIT 20
  `;
  console.log('Categorias en Product:', JSON.stringify(cats, null, 2));
}

main().catch(e => {
  console.error(e.message);
  // Try lowercase
  return p.$queryRaw`SELECT DISTINCT categoria, COUNT(*) as total FROM product GROUP BY categoria ORDER BY total DESC LIMIT 20`
    .then(r => console.log('Categorias (lowercase table):', JSON.stringify(r, null, 2)));
}).finally(() => p.$disconnect());
