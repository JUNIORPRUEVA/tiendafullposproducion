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
    { nombre: `Producto Smoke ${Date.now()}`, categoria: 'General', precio: 100, costo: 70 },
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

  const uploadPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9l9JYAAAAASUVORK5CYII=';
  const uploadBytes = Buffer.from(uploadPngBase64, 'base64');
  const form = new FormData();
  form.append(
    'file',
    new Blob([uploadBytes], { type: 'image/png' }),
    `smoke-user-doc-${Date.now()}.png`
  );

  const uploadRes = await fetch(`${baseUrl}/users/upload`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${refreshedAccessToken}`,
    },
    body: form,
  });

  const uploadText = await uploadRes.text();
  const uploaded = uploadText ? (JSON.parse(uploadText) as Json) : ({} as Json);
  if (!uploadRes.ok) {
    throw new Error(`POST /users/upload failed ${uploadRes.status}: ${uploadText}`);
  }
  if (!uploaded.url && !uploaded.path) {
    throw new Error('Upload response missing url/path');
  }
  console.log('user upload ok');

  const seed = Date.now();
  const newEmail = `smoke.user.${seed}@fulltech.local`;
  const newCedula = `SMK-${seed}`;
  const createUserPayload = {
    email: newEmail,
    password: 'SmokePass123!',
    nombreCompleto: `Smoke User ${seed}`,
    telefono: '8090000001',
    telefonoFamiliar: '8090000002',
    cedula: newCedula,
    fotoCedulaUrl: uploaded.url ?? uploaded.path,
    fotoLicenciaUrl: uploaded.url ?? uploaded.path,
    fotoPersonalUrl: uploaded.url ?? uploaded.path,
    edad: 30,
    role: 'ASISTENTE',
    blocked: false,
  };

  const createdUser = await http('POST', '/users', createUserPayload, refreshedAccessToken);
  if (!createdUser?.id) throw new Error('User create missing id');
  console.log('user created', createdUser.id);

  const usersList = await http('GET', '/users', undefined, refreshedAccessToken);
  if (!Array.isArray(usersList)) throw new Error('Expected users array');
  if (!usersList.some((u: Json) => u.id === createdUser.id)) {
    throw new Error('Created user not found in users list');
  }
  console.log('users list ok');

  const updatedUser = await http(
    'PATCH',
    `/users/${createdUser.id}`,
    {
      nombreCompleto: `Smoke User Updated ${seed}`,
      telefono: '8090000010',
      telefonoFamiliar: '8090000011',
      edad: 31,
      fotoPersonalUrl: uploaded.url ?? uploaded.path,
    },
    refreshedAccessToken
  );
  if (updatedUser.nombreCompleto !== `Smoke User Updated ${seed}`) {
    throw new Error('User update did not persist nombreCompleto');
  }
  console.log('user update ok');

  const blockedUser = await http(
    'PATCH',
    `/users/${createdUser.id}/block`,
    { blocked: true },
    refreshedAccessToken
  );
  if (blockedUser.blocked !== true) {
    throw new Error('User block endpoint did not set blocked=true');
  }
  console.log('user block ok');

  const unblockedUser = await http(
    'PATCH',
    `/users/${createdUser.id}/block`,
    { blocked: false },
    refreshedAccessToken
  );
  if (unblockedUser.blocked !== false) {
    throw new Error('User block endpoint did not set blocked=false');
  }
  console.log('user unblock ok');

  await http('DELETE', `/users/${createdUser.id}`, undefined, refreshedAccessToken);
  console.log('user delete ok');

  console.log('SMOKE TEST OK');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
