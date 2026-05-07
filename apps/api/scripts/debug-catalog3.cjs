require('dotenv').config({ path: require('path').join(__dirname, '../.env') });

const FULLPOS_BASE = (process.env.FULLPOS_INTEGRATION_BASE_URL || '').trim().replace(/\/$/, '');
const FULLPOS_TOKEN = process.env.FULLPOS_INTEGRATION_TOKEN || '';

const CAMERA_KEYWORDS = [
  'camara', 'cámara', 'camera', 'cam ', ' cam', 'dvr', 'nvr', 'cctv',
  'motor', 'porton', 'portón', 'domo', 'bala', 'bullet',
  'hikvision', 'dahua', 'reolink', 'tp-link', 'imou',
  'vigilancia', 'seguridad', 'ip67', '4mp', '8mp', '2mp', '5mp',
  'turbo hd', 'turbo-hd', 'hd poe', 'poe',
];

async function main() {
  const url = FULLPOS_BASE + '/api/integrations/products?limit=500';
  const res = await fetch(url, {
    headers: { Authorization: 'Bearer ' + FULLPOS_TOKEN, Accept: 'application/json' },
  });
  const data = await res.json();
  const items = Array.isArray(data) ? data : data.items || data.data || data.products || data.rows || [];

  console.log('Total:', items.length);

  const withImg = items.filter(p => (p.image_url || '').trim().length > 0);
  console.log('With image:', withImg.length);

  // Security products by name
  const securityProducts = items.filter(p => {
    const name = (p.name || p.nombre || '').toLowerCase();
    return CAMERA_KEYWORDS.some(kw => name.includes(kw));
  });
  const securityWithImg = securityProducts.filter(p => (p.image_url || '').trim().length > 0);

  console.log('\nSecurity products by name:', securityProducts.length);
  console.log('Security products with image:', securityWithImg.length);

  console.log('\n--- SECURITY PRODUCTS WITH IMAGE ---');
  securityWithImg.forEach(p => {
    console.log(`  "${p.name}" | ${(p.image_url || '').substring(0, 70)}`);
  });

  console.log('\n--- ALL SECURITY PRODUCTS (no img) ---');
  securityProducts.filter(p => !(p.image_url || '').trim().length).forEach(p => {
    console.log(`  NO IMG: "${p.name}"`);
  });
}

main().catch(e => console.error('ERROR:', e.message));
