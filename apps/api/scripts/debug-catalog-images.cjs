const { PrismaClient } = require('@prisma/client');
const p = new PrismaClient();

// Read env for FullPOS URL
require('dotenv').config({ path: require('path').join(__dirname, '../.env') });

const FULLPOS_BASE = (process.env.FULLPOS_INTEGRATION_BASE_URL || '').trim().replace(/\/$/, '');
const FULLPOS_TOKEN = process.env.FULLPOS_INTEGRATION_TOKEN || '';

async function main() {
  if (!FULLPOS_BASE) {
    console.log('FULLPOS_INTEGRATION_BASE_URL not configured — checking local Product table only');
    const cats = await p.product.groupBy({ by: ['categoria'], _count: { id: true } });
    console.log('Local Product categories:', JSON.stringify(cats));
    return;
  }

  console.log('Fetching from:', FULLPOS_BASE + '/catalog/products');
  const res = await fetch(FULLPOS_BASE + '/catalog/products', {
    headers: FULLPOS_TOKEN ? { Authorization: `Bearer ${FULLPOS_TOKEN}` } : {},
  });
  const data = await res.json();
  const items = data.items || data.data || data.products || data || [];
  console.log('Total products:', items.length);

  // Count by category
  const byCat = {};
  for (const p of items) {
    const cat = p.categoriaNombre || p.categoria || 'null';
    byCat[cat] = (byCat[cat] || 0) + 1;
  }
  console.log('\nCategories:');
  Object.entries(byCat).sort((a, b) => b[1] - a[1]).forEach(([cat, count]) => {
    console.log(`  "${cat}": ${count} productos`);
  });

  // Products in Sistema de Vigilancia with images
  const vigilancia = items.filter(p => {
    const cat = (p.categoriaNombre || p.categoria || '').toLowerCase();
    return cat.includes('vigilancia') || cat.includes('videovigilancia');
  });
  const withImg = vigilancia.filter(p => p.fotoUrl || p.imagen);
  console.log(`\n"Sistema de Vigilancia" total: ${vigilancia.length}, with image: ${withImg.length}`);

  console.log('\nProducts with images:');
  withImg.slice(0, 20).forEach(p => {
    console.log(`  [${p.id}] "${p.nombre}" | cat: "${p.categoriaNombre || p.categoria}" | img: ${(p.fotoUrl || p.imagen || '').substring(0, 80)}`);
  });
}

main().catch(console.error).finally(() => p.$disconnect());
