/* eslint-disable no-console */

type Json = Record<string, any>;

const baseUrl = `http://localhost:${process.env.PORT ?? 4000}`;
const adminEmail = process.env.ADMIN_EMAIL ?? 'admin@fulltech.local';
const adminPassword = process.env.ADMIN_PASSWORD;
if (!adminPassword) {
  throw new Error('ADMIN_PASSWORD is required to run smoke test');
}

async function http(method: string, path: string, body?: any, token?: string) {
  const res = await fetch(`${baseUrl}${path}`, {
    method,
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {})
    },
    body: body ? JSON.stringify(body) : undefined
  });

  const text = await res.text();
  const json = text ? (JSON.parse(text) as Json) : ({} as Json);
  if (!res.ok) {
    throw new Error(`${method} ${path} failed ${res.status}: ${text}`);
  }
  return json;
}

async function waitForHealth(timeoutMs = 30_000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      const j = await http('GET', '/health');
      if (j.status === 'ok') return;
    } catch {}
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error('Health check timed out');
}

async function main() {
  await waitForHealth();
  console.log('health ok');

  const login = await http('POST', '/auth/login', {
    identifier: adminEmail,
    password: adminPassword
  });
  const token = login.accessToken as string;
  if (!token) throw new Error('Missing accessToken');
  const refreshToken = login.refreshToken as string | undefined;
  if (!refreshToken) throw new Error('Missing refreshToken');
  console.log('login ok');

  const refreshed = await http('POST', '/auth/refresh', { refreshToken });
  const refreshedAccessToken = refreshed.accessToken as string;
  if (!refreshedAccessToken) throw new Error('Missing refreshed accessToken');
  console.log('refresh ok');

  const product = await http(
    'POST',
    '/products',
    { nombre: `Producto Smoke ${Date.now()}`, precio: 100, costo: 70 },
    refreshedAccessToken
  );
  console.log('product created', product.id);

  const products = await http('GET', '/products', undefined, refreshedAccessToken);
  if (!Array.isArray(products)) throw new Error('Expected products array');
  console.log('products list ok');

  const client = await http(
    'POST',
    '/clients',
    { nombre: `Cliente Smoke ${Date.now()}`, telefono: '0000000000' },
    refreshedAccessToken
  );
  console.log('client created', client.id);

  console.log('SMOKE TEST OK');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
