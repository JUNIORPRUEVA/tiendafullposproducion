const fs = require('fs');
const { PrismaClient } = require('@prisma/client');
const jwt = require('jsonwebtoken');

const prisma = new PrismaClient();
const base = 'http://localhost:4000';
const dateFrom = '2026-05-01';
const dateTo = '2026-05-14';
const missingId = '00000000-0000-4000-8000-000000000000';

function envValue(name, fallback = '') {
  const text = fs.readFileSync('.env', 'utf8');
  const line = text.split(/\r?\n/).find((row) => row.trim().startsWith(`${name}=`));
  if (!line) return fallback;
  return line.substring(line.indexOf('=') + 1).trim().replace(/^"|"$/g, '');
}

function token(user) {
  return jwt.sign(
    { sub: user.id, email: user.email, role: user.role, tokenType: 'access' },
    envValue('JWT_SECRET', 'change-me'),
    { expiresIn: '15m' },
  );
}

async function req(label, role, method, path, tokenValue, body) {
  const res = await fetch(`${base}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${tokenValue}`,
      'Content-Type': 'application/json',
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let data = null;
  try {
    data = await res.json();
  } catch {
    data = await res.text();
  }
  const message = data && typeof data === 'object' ? data.message : data;
  return {
    label,
    role,
    method,
    path,
    status: res.status,
    message,
    count: Array.isArray(data) ? data.length : undefined,
  };
}

(async () => {
  const admin = await prisma.user.findFirst({
    where: { role: 'ADMIN' },
    select: { id: true, email: true, role: true, nombreCompleto: true },
  });
  const assistant = await prisma.user.findFirst({
    where: { role: 'ASISTENTE' },
    orderBy: { nombreCompleto: 'asc' },
    select: { id: true, email: true, role: true, nombreCompleto: true },
  });
  if (!admin || !assistant) throw new Error('Missing admin or assistant users');

  const adminToken = token(admin);
  const assistantToken = token(assistant);
  const adminPassword = envValue('ADMIN_PASSWORD', '');
  const ownClose = await prisma.close.findFirst({
    where: { createdById: assistant.id },
    orderBy: { createdAt: 'desc' },
    select: { id: true, createdById: true },
  });
  const otherClose = await prisma.close.findFirst({
    where: { createdById: { not: assistant.id } },
    orderBy: { createdAt: 'desc' },
    select: { id: true, createdById: true },
  });
  const allDb = await prisma.close.count({
    where: { date: { gte: new Date(dateFrom), lte: new Date(dateTo) } },
  });
  const ownDb = await prisma.close.count({
    where: {
      createdById: assistant.id,
      date: { gte: new Date(dateFrom), lte: new Date(dateTo) },
    },
  });

  const tests = [];
  tests.push(await req('GET list', 'ADMIN', 'GET', `/contabilidad/closes?from=${dateFrom}&to=${dateTo}`, adminToken));
  tests.push(await req('GET list own-scope', 'ASISTENTE', 'GET', `/contabilidad/closes?from=${dateFrom}&to=${dateTo}`, assistantToken));
  tests.push(await req('POST create validation-only', 'ADMIN', 'POST', '/contabilidad/closes', adminToken, {}));
  tests.push(await req('POST create validation-only', 'ASISTENTE', 'POST', '/contabilidad/closes', assistantToken, {}));
  if (ownClose) tests.push(await req('GET own detail', 'ASISTENTE', 'GET', `/contabilidad/closes/${ownClose.id}`, assistantToken));
  if (otherClose) tests.push(await req('GET other detail', 'ASISTENTE', 'GET', `/contabilidad/closes/${otherClose.id}`, assistantToken));
  tests.push(await req('PUT update missing', 'ADMIN', 'PUT', `/contabilidad/closes/${missingId}`, adminToken, {}));
  tests.push(await req('PUT update forbidden', 'ASISTENTE', 'PUT', `/contabilidad/closes/${missingId}`, assistantToken, {}));
  tests.push(await req('DELETE missing with admin password', 'ADMIN', 'DELETE', `/contabilidad/closes/${missingId}`, adminToken, { adminPassword }));
  tests.push(await req('DELETE forbidden', 'ASISTENTE', 'DELETE', `/contabilidad/closes/${missingId}`, assistantToken, { adminPassword: 'x' }));
  tests.push(await req('POST approve missing', 'ADMIN', 'POST', `/contabilidad/closes/${missingId}/approve`, adminToken, { reviewNote: 'audit' }));
  tests.push(await req('POST approve forbidden', 'ASISTENTE', 'POST', `/contabilidad/closes/${missingId}/approve`, assistantToken, { reviewNote: 'audit' }));
  tests.push(await req('POST reject missing', 'ADMIN', 'POST', `/contabilidad/closes/${missingId}/reject`, adminToken, { reviewNote: 'audit rejection' }));
  tests.push(await req('POST reject forbidden', 'ASISTENTE', 'POST', `/contabilidad/closes/${missingId}/reject`, assistantToken, { reviewNote: 'audit' }));
  tests.push(await req('GET financial summary', 'ADMIN', 'GET', `/contabilidad/closes/financial-summary?fromDate=${dateFrom}&toDate=${dateTo}`, adminToken));
  tests.push(await req('GET financial summary forbidden', 'ASISTENTE', 'GET', `/contabilidad/closes/financial-summary?fromDate=${dateFrom}&toDate=${dateTo}`, assistantToken));
  tests.push(await req('POST AI report missing', 'ADMIN', 'POST', `/contabilidad/closes/${missingId}/ai-report`, adminToken));
  tests.push(await req('POST AI report forbidden', 'ASISTENTE', 'POST', `/contabilidad/closes/${missingId}/ai-report`, assistantToken));
  tests.push(await req('GET non-existing PDF route', 'ADMIN', 'GET', `/contabilidad/closes/${missingId}/pdf`, adminToken));

  console.log(JSON.stringify({
    users: {
      admin,
      assistant,
    },
    dbCounts: {
      allDb,
      ownDb,
      assistantId: assistant.id,
      ownCloseId: ownClose?.id || null,
      otherCloseId: otherClose?.id || null,
    },
    tests,
  }, null, 2));
})()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => prisma.$disconnect());
