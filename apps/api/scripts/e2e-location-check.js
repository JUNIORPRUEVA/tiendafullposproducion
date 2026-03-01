/*
  E2E check (no secrets printed):
  - reads ADMIN_EMAIL / ADMIN_PASSWORD from apps/api/.env
  - POST /auth/login
  - POST /locations
  - GET /admin/locations/latest
*/

const fs = require('node:fs');
const path = require('node:path');

function parseDotEnv(text) {
  const out = {};
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const idx = trimmed.indexOf('=');
    if (idx <= 0) continue;
    const key = trimmed.slice(0, idx).trim();
    let value = trimmed.slice(idx + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    out[key] = value;
  }
  return out;
}

async function main() {
  const envPath = path.join(__dirname, '..', '.env');
  if (!fs.existsSync(envPath)) {
    console.error('Missing env file:', envPath);
    process.exit(1);
  }

  const env = parseDotEnv(fs.readFileSync(envPath, 'utf8'));
  const email = (env.ADMIN_EMAIL || 'admin@fulltech.local').trim();
  const password = (env.ADMIN_PASSWORD || '').trim();

  if (!password) {
    console.error('ADMIN_PASSWORD missing in apps/api/.env (cannot auto-login for E2E)');
    process.exit(2);
  }

  const base = 'http://localhost:4000';

  const loginRes = await fetch(base + '/auth/login', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });

  if (!loginRes.ok) {
    const body = await loginRes.text().catch(() => '');
    console.error('Login failed:', loginRes.status, body.slice(0, 500));
    process.exit(3);
  }

  const login = await loginRes.json();
  const token = login && login.accessToken;
  if (!token) {
    console.error('No accessToken in /auth/login response');
    process.exit(4);
  }

  const reportRes = await fetch(base + '/locations', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: 'Bearer ' + token,
    },
    body: JSON.stringify({
      latitude: 18.486057,
      longitude: -69.931212,
      accuracyMeters: 12,
      recordedAt: new Date().toISOString(),
    }),
  });

  if (!reportRes.ok) {
    const body = await reportRes.text().catch(() => '');
    console.error('Report location failed:', reportRes.status, body.slice(0, 500));
    process.exit(5);
  }

  const latestRes = await fetch(base + '/admin/locations/latest', {
    headers: { authorization: 'Bearer ' + token },
  });

  if (!latestRes.ok) {
    const body = await latestRes.text().catch(() => '');
    console.error('Latest locations failed:', latestRes.status, body.slice(0, 500));
    process.exit(6);
  }

  const latest = await latestRes.json();
  const count = Array.isArray(latest) ? latest.length : 0;
  console.log('E2E OK. latest_count=', count);
}

main().catch((e) => {
  console.error('E2E error:', e && e.message ? e.message : String(e));
  process.exit(9);
});
