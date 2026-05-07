require('dotenv').config({ path: require('path').join(__dirname, '../.env') });

const FULLPOS_BASE = (process.env.FULLPOS_INTEGRATION_BASE_URL || '').trim().replace(/\/$/, '');
const FULLPOS_TOKEN = process.env.FULLPOS_INTEGRATION_TOKEN || '';

async function main() {
  const url = FULLPOS_BASE + '/api/integrations/products?limit=500';
  console.log('Fetching:', url);

  const res = await fetch(url, {
    headers: { Authorization: 'Bearer ' + FULLPOS_TOKEN, Accept: 'application/json' },
  });
  console.log('Status:', res.status);
  const raw = await res.text();
  let data;
  try { data = JSON.parse(raw); } catch { console.log('Not JSON:', raw.substring(0, 300)); return; }

  const items = Array.isArray(data) ? data
    : data.items || data.data || data.products || data.rows || [];
  console.log('Total products:', items.length);

  if (items.length === 0) {
    console.log('Response sample:', JSON.stringify(data).substring(0, 500));
    return;
  }

  // Show one sample to understand field names
  console.log('\nSample product keys:', Object.keys(items[0]));
  console.log('Sample product:', JSON.stringify(items[0], null, 2).substring(0, 600));

  // Categories
  const byCat = {};
  for (const p of items) {
    const cat = p.categoriaNombre || p.categoria || p.category_name || (p.category && (p.category.name || p.category)) || 'NULL';
    byCat[cat] = (byCat[cat] || 0) + 1;
  }
  console.log('\nCategories:');
  Object.entries(byCat).sort((a, b) => b[1] - a[1]).slice(0, 20).forEach(([cat, count]) => {
    console.log(`  "${cat}": ${count}`);
  });

  // Filter vigilancia
  const vigilancia = items.filter(p => {
    const cat = (p.categoriaNombre || p.categoria || p.category_name || (p.category?.name || '') || '').toLowerCase();
    return cat.includes('vigilancia') || cat.includes('videovigilancia');
  });
  const withImg = vigilancia.filter(p => {
    const img = p.fotoUrl || p.imagen || p.image_url || p.imageUrl || '';
    return img.trim().length > 0;
  });
  console.log(`\nSistema de Vigilancia: ${vigilancia.length} total, ${withImg.length} con imagen`);

  console.log('\nProductos con imagen:');
  withImg.slice(0, 20).forEach(p => {
    const img = p.fotoUrl || p.imagen || p.image_url || p.imageUrl || '';
    console.log(`  "${p.nombre || p.name}" | img: ${img.substring(0, 80)}`);
  });
}

main().catch(e => console.error('ERROR:', e.message));
