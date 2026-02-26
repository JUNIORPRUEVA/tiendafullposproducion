/* eslint-disable no-console */

export {};

type Json = Record<string, any>;

const baseUrl = `http://localhost:${process.env.PORT ?? 4000}`;
const adminEmail = process.env.ADMIN_EMAIL ?? 'admin@fulltech.local';
const adminPassword = process.env.ADMIN_PASSWORD;

if (!adminPassword) {
  throw new Error('ADMIN_PASSWORD is required');
}

async function http(method: string, path: string, body?: unknown, token?: string) {
  const res = await fetch(`${baseUrl}${path}`, {
    method,
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });

  const text = await res.text();
  const json = text ? (JSON.parse(text) as Json) : {};

  if (!res.ok) {
    throw new Error(`${method} ${path} failed ${res.status}: ${text}`);
  }

  return json;
}

async function main() {
  const login = await http('POST', '/auth/login', {
    identifier: adminEmail,
    password: adminPassword,
  });
  const token = login.accessToken as string;
  if (!token) throw new Error('No access token');

  const ts = Date.now();
  const product = await http(
    'POST',
    '/products',
    { nombre: `Producto Venta Smoke ${ts}`, categoria: 'General', precio: 120, costo: 80 },
    token,
  );

  const client = await http(
    'POST',
    '/clients',
    { nombre: `Cliente Venta Smoke ${ts}`, telefono: '8090001000' },
    token,
  );

  const sale = await http(
    'POST',
    '/sales',
    {
      customerId: client.id,
      note: 'Venta smoke test',
      items: [
        {
          productId: product.id,
          qty: 2,
          priceSoldUnit: 120,
        },
      ],
    },
    token,
  );

  if (!sale?.id) throw new Error('Sale create missing id');
  console.log('sale create ok', sale.id);

  const now = new Date();
  const fromDate = new Date(now.getTime() - 24 * 60 * 60 * 1000);
  const toDate = new Date(now.getTime() + 24 * 60 * 60 * 1000);
  const from = `${fromDate.getUTCFullYear()}-${String(fromDate.getUTCMonth() + 1).padStart(2, '0')}-${String(fromDate.getUTCDate()).padStart(2, '0')}`;
  const to = `${toDate.getUTCFullYear()}-${String(toDate.getUTCMonth() + 1).padStart(2, '0')}-${String(toDate.getUTCDate()).padStart(2, '0')}`;

  const list = await http('GET', `/sales?from=${from}&to=${to}`, undefined, token);
  if (!Array.isArray(list)) throw new Error('Sales list invalid');
  if (!list.some((row: Json) => row.id === sale.id)) {
    throw new Error('Created sale not found in list');
  }
  console.log('sales list ok');

  const summary = await http('GET', `/sales/summary?from=${from}&to=${to}`, undefined, token);
  if (typeof summary.totalSales !== 'number') {
    throw new Error('Sales summary invalid');
  }
  console.log('sales summary ok', summary.totalSales);

  await http('DELETE', `/sales/${sale.id}`, undefined, token);
  console.log('sale delete ok');

  console.log('SALES SMOKE OK');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
