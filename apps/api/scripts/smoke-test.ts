/* eslint-disable no-console */

type Json = Record<string, any>;

const baseUrl = `http://localhost:${process.env.PORT ?? 4000}`;

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
    email: 'admin@fulltech.local',
    password: 'Admin12345!'
  });
  const token = login.accessToken as string;
  if (!token) throw new Error('Missing accessToken');
  console.log('login ok');

  const product = await http(
    'POST',
    '/products',
    { nombre: `Producto Smoke ${Date.now()}`, precio: 100, costo: 70 },
    token
  );
  console.log('product created', product.id);

  const products = await http('GET', '/products', undefined, token);
  if (!Array.isArray(products)) throw new Error('Expected products array');
  console.log('products list ok');

  const client = await http(
    'POST',
    '/clients',
    { nombre: `Cliente Smoke ${Date.now()}`, telefono: '0000000000' },
    token
  );
  console.log('client created', client.id);

  console.log('SMOKE TEST OK');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
