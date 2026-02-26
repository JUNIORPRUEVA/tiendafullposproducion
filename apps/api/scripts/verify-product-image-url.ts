/* eslint-disable no-console */

export {};

type Json = Record<string, any>;

const baseUrl = (process.env.API_BASE_URL ?? 'http://localhost:4000').replace(/\/$/, '');
const adminEmail = process.env.ADMIN_EMAIL ?? 'admin@fulltech.local';
const adminPassword = process.env.ADMIN_PASSWORD;

if (!adminPassword) {
  throw new Error('ADMIN_PASSWORD is required');
}

async function main() {
  const loginRes = await fetch(`${baseUrl}/auth/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ identifier: adminEmail, password: adminPassword }),
  });

  const loginBody = (await loginRes.json()) as Json;
  if (!loginRes.ok || !loginBody.accessToken) {
    throw new Error(`Login failed: ${loginRes.status} ${JSON.stringify(loginBody)}`);
  }

  const token = loginBody.accessToken as string;
  const productsRes = await fetch(`${baseUrl}/products`, {
    headers: { authorization: `Bearer ${token}` },
  });

  const productsBody = (await productsRes.json()) as Json[];
  if (!productsRes.ok || !Array.isArray(productsBody)) {
    throw new Error(`Products failed: ${productsRes.status} ${JSON.stringify(productsBody)}`);
  }

  const withImage = productsBody.find((p) => typeof p?.fotoUrl === 'string' && p.fotoUrl.length > 0);
  if (!withImage) {
    throw new Error('No products with fotoUrl found');
  }

  const imageUrl = withImage.fotoUrl as string;
  const imageRes = await fetch(imageUrl, { method: 'GET' });

  console.log('[verify] product id:', withImage.id);
  console.log('[verify] imageUrl:', imageUrl);
  console.log('[verify] status:', imageRes.status);

  if (imageRes.status !== 200) {
    throw new Error(`Image URL not reachable: ${imageUrl} status=${imageRes.status}`);
  }

  console.log('OK: image URL returns 200');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
