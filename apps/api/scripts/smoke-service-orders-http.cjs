#!/usr/bin/env node

/* eslint-disable no-console */

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { PrismaClient, Role } = require('@prisma/client');

const prisma = new PrismaClient();
const baseUrl = `http://localhost:${process.env.PORT ?? 4000}`;
const qaTag = `qa-service-orders-http-${Date.now()}`;

const created = {
  orderIds: [],
  evidenceIds: [],
  reportIds: [],
  quotationIds: [],
  clientIds: [],
  userIds: [],
};

const results = [];
const findings = [];

function parseEnvFile() {
  const envPath = path.join(__dirname, '..', '.env');
  if (!fs.existsSync(envPath)) return;

  const lines = fs.readFileSync(envPath, 'utf8').split(/\r?\n/);
  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const separator = line.indexOf('=');
    if (separator < 0) continue;
    const key = line.slice(0, separator).trim();
    if (!key || process.env[key] != null) continue;
    let value = line.slice(separator + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    process.env[key] = value;
  }
}

function randomUuid() {
  return crypto.randomUUID();
}

function recordPass(name, details) {
  results.push({ status: 'PASS', name, details: details ?? null });
  console.log(`PASS ${name}`);
  if (details) console.log(`  ${details}`);
}

function recordFinding(message) {
  findings.push(message);
  console.warn(`FINDING ${message}`);
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function http(method, route, body, token, expectedStatuses) {
  const response = await fetch(`${baseUrl}${route}`, {
    method,
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });

  const text = await response.text();
  let json = null;
  if (text) {
    try {
      json = JSON.parse(text);
    } catch {
      json = text;
    }
  }

  const allowed = Array.isArray(expectedStatuses) ? expectedStatuses : [expectedStatuses];
  if (!allowed.includes(response.status)) {
    throw new Error(`${method} ${route} expected ${allowed.join('/')} but received ${response.status}: ${text}`);
  }

  return { status: response.status, body: json };
}

async function waitForHealth(timeoutMs = 30000) {
  const startedAt = Date.now();
  while (Date.now() - startedAt < timeoutMs) {
    try {
      const response = await fetch(`${baseUrl}/health`);
      if (response.ok) {
        const json = await response.json();
        if (json?.status === 'ok') return;
      }
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 750));
  }
  throw new Error('Health check timed out');
}

async function createQaUser(label, role = Role.ADMIN) {
  const user = await prisma.user.create({
    data: {
      email: `${label}-${Date.now()}@fulltech.local`,
      passwordHash: 'qa-test-hash',
      nombreCompleto: `QA ${label}`,
      telefono: '8095550000',
      edad: 30,
      role,
    },
  });
  created.userIds.push(user.id);
  return user;
}

async function createFixtures() {
  const owner = await createQaUser('service-orders-http-owner', Role.ADMIN);
  const technician = await createQaUser('service-orders-http-tech', Role.TECNICO);
  const client = await prisma.client.create({
    data: {
      ownerId: owner.id,
      nombre: `Cliente ${qaTag}`,
      telefono: '8095552200',
      notas: qaTag,
    },
  });
  created.clientIds.push(client.id);

  const quotation = await prisma.cotizacion.create({
    data: {
      createdByUserId: owner.id,
      customerId: client.id,
      customerName: client.nombre,
      customerPhone: client.telefono,
      note: qaTag,
      includeItbis: false,
      subtotal: 1000,
      itbisAmount: 0,
      total: 1000,
    },
  });
  created.quotationIds.push(quotation.id);

  return { owner, technician, client, quotation };
}

async function cleanup() {
  if (created.reportIds.length) {
    await prisma.serviceReport.deleteMany({ where: { id: { in: created.reportIds } } });
  }
  if (created.evidenceIds.length) {
    await prisma.serviceEvidence.deleteMany({ where: { id: { in: created.evidenceIds } } });
  }
  if (created.orderIds.length) {
    await prisma.serviceOrder.deleteMany({ where: { id: { in: created.orderIds } } });
  }
  if (created.quotationIds.length) {
    await prisma.cotizacion.deleteMany({ where: { id: { in: created.quotationIds } } });
  }
  if (created.clientIds.length) {
    await prisma.client.deleteMany({ where: { id: { in: created.clientIds } } });
  }
  if (created.userIds.length) {
    await prisma.user.deleteMany({ where: { id: { in: created.userIds } } });
  }
}

async function main() {
  parseEnvFile();
  await waitForHealth();

  const adminEmail = process.env.ADMIN_EMAIL ?? 'admin@fulltech.local';
  const adminPassword = process.env.ADMIN_PASSWORD ?? '';
  if (!adminPassword) {
    throw new Error('ADMIN_PASSWORD is required');
  }

  const login = await http('POST', '/auth/login', {
    identifier: adminEmail,
    password: adminPassword,
  }, undefined, 201);
  const token = login.body?.accessToken;
  assert(token, 'Login did not return accessToken');
  recordPass('Auth login', 'token recibido');

  const fixture = await createFixtures();

  const createResponse = await http(
    'POST',
    '/service-orders',
    {
      client_id: fixture.client.id,
      quotation_id: fixture.quotation.id,
      category: 'camara',
      service_type: 'instalacion',
      status: 'pendiente',
      technical_note: 'Nota inicial HTTP',
      extra_requirements: 'Requiere escalera',
      assigned_to: fixture.technician.id,
    },
    token,
    201,
  );
  const createdOrder = createResponse.body;
  created.orderIds.push(createdOrder.id);
  assert(createdOrder.clientId === fixture.client.id, 'POST /service-orders did not persist clientId');
  assert(createdOrder.quotationId === fixture.quotation.id, 'POST /service-orders did not persist quotationId');
  assert(createdOrder.category === 'camara', 'POST /service-orders returned wrong category');
  assert(createdOrder.serviceType === 'instalacion', 'POST /service-orders returned wrong serviceType');
  assert(createdOrder.status === 'pendiente', 'POST /service-orders returned wrong status');
  recordPass('POST /service-orders', createdOrder.id);

  const listResponse = await http('GET', '/service-orders', undefined, token, 200);
  assert(Array.isArray(listResponse.body?.items), 'GET /service-orders did not return items array');
  assert(listResponse.body.items.some((item) => item.id === createdOrder.id), 'Created order missing from GET /service-orders');
  recordPass('GET /service-orders', `items=${listResponse.body.items.length}`);

  const invalidCreate = await http(
    'POST',
    '/service-orders',
    {
      client_id: fixture.client.id,
      quotation_id: fixture.quotation.id,
      category: 'categoria_invalida',
      service_type: 'instalacion',
      status: 'pendiente',
    },
    token,
    400,
  );
  assert(String(invalidCreate.body?.message ?? '').includes('category'), 'Invalid category did not return validation error');
  recordPass('POST /service-orders invalid enum', '400 esperado');

  const missingField = await http(
    'POST',
    '/service-orders',
    {
      quotation_id: fixture.quotation.id,
      category: 'camara',
      service_type: 'instalacion',
      status: 'pendiente',
    },
    token,
    400,
  );
  assert(String(missingField.body?.message ?? '').includes('client_id'), 'Missing client_id did not return expected message');
  recordPass('POST /service-orders missing field', '400 esperado');

  const evidenceText = await http(
    'POST',
    `/service-orders/${createdOrder.id}/evidences`,
    { type: 'referencia_texto', content: 'Texto HTTP QA' },
    token,
    201,
  );
  created.evidenceIds.push(evidenceText.body.id);

  const evidenceImage = await http(
    'POST',
    `/service-orders/${createdOrder.id}/evidences`,
    { type: 'referencia_imagen', content: 'https://example.com/evidence.jpg' },
    token,
    201,
  );
  created.evidenceIds.push(evidenceImage.body.id);

  const evidenceVideo = await http(
    'POST',
    `/service-orders/${createdOrder.id}/evidences`,
    { type: 'evidencia_video', content: 'https://example.com/evidence.mp4' },
    token,
    201,
  );
  created.evidenceIds.push(evidenceVideo.body.id);
  recordPass('POST /service-orders/:id/evidences', '3 evidencias creadas');

  const reportResponse = await http(
    'POST',
    `/service-orders/${createdOrder.id}/report`,
    { report: 'Reporte HTTP QA' },
    token,
    201,
  );
  created.reportIds.push(reportResponse.body.id);
  recordPass('POST /service-orders/:id/report', reportResponse.body.id);

  const detailResponse = await http('GET', `/service-orders/${createdOrder.id}`, undefined, token, 200);
  assert(Array.isArray(detailResponse.body?.evidences), 'GET /service-orders/:id missing evidences array');
  assert(Array.isArray(detailResponse.body?.reports), 'GET /service-orders/:id missing reports array');
  assert(detailResponse.body.evidences.length === 3, 'GET /service-orders/:id should include 3 evidences');
  assert(detailResponse.body.reports.length === 1, 'GET /service-orders/:id should include 1 report');
  recordPass('GET /service-orders/:id', createdOrder.id);

  const inProgress = await http(
    'PATCH',
    `/service-orders/${createdOrder.id}/status`,
    { status: 'en_proceso' },
    token,
    200,
  );
  assert(inProgress.body.status === 'en_proceso', 'Status did not change to en_proceso');

  const finalized = await http(
    'PATCH',
    `/service-orders/${createdOrder.id}/status`,
    { status: 'finalizado' },
    token,
    200,
  );
  assert(finalized.body.status === 'finalizado', 'Status did not change to finalizado');
  recordPass('PATCH /service-orders/:id/status valid transitions', 'pendiente -> en_proceso -> finalizado');

  const invalidTransition = await http(
    'PATCH',
    `/service-orders/${createdOrder.id}/status`,
    { status: 'pendiente' },
    token,
    400,
  );
  assert(String(invalidTransition.body?.message ?? '').includes('Transición inválida'), 'Invalid transition did not return expected error');
  recordPass('PATCH /service-orders/:id/status invalid transition', '400 esperado');

  const invalidStatus = await http(
    'PATCH',
    `/service-orders/${createdOrder.id}/status`,
    { status: 'estado_invalido' },
    token,
    400,
  );
  assert(String(invalidStatus.body?.message ?? '').includes('status'), 'Invalid status enum did not return validation error');
  recordPass('PATCH /service-orders/:id/status invalid enum', '400 esperado');

  const cloneResponse = await http(
    'POST',
    `/service-orders/${createdOrder.id}/clone`,
    {
      service_type: 'garantia',
      technical_note: 'Clon HTTP QA',
      assigned_to: fixture.technician.id,
    },
    token,
    201,
  );
  const clonedOrder = cloneResponse.body;
  created.orderIds.push(clonedOrder.id);
  assert(clonedOrder.clientId === createdOrder.clientId, 'Clone did not copy clientId');
  assert(clonedOrder.quotationId === createdOrder.quotationId, 'Clone did not copy quotationId');
  assert(clonedOrder.parentOrderId === createdOrder.id, 'Clone did not set parentOrderId');
  assert(clonedOrder.serviceType === 'garantia', 'Clone did not apply new service type');
  assert(clonedOrder.status === 'pendiente', 'Clone did not reset status to pendiente');
  recordPass('POST /service-orders/:id/clone', clonedOrder.id);

  const notFoundGet = await http('GET', `/service-orders/${randomUuid()}`, undefined, token, 404);
  assert(String(notFoundGet.body?.message ?? '').includes('no encontrada'), 'GET missing id did not return not found message');
  recordPass('GET /service-orders/:id non-existing', '404 esperado');

  const notFoundEvidence = await http(
    'POST',
    `/service-orders/${randomUuid()}/evidences`,
    { type: 'texto', content: 'test' },
    token,
    404,
  );
  assert(String(notFoundEvidence.body?.message ?? '').includes('no encontrada'), 'Evidence on missing order did not return not found');
  recordPass('POST /service-orders/:id/evidences non-existing', '404 esperado');

  const reportMissingField = await http(
    'POST',
    `/service-orders/${createdOrder.id}/report`,
    {},
    token,
    400,
  );
  const reportMessage = reportMissingField.body?.message;
  if (Array.isArray(reportMessage)) {
    assert(reportMessage.some((item) => String(item).includes('report')), 'Missing report field did not mention report');
  } else {
    assert(String(reportMessage ?? '').includes('report'), 'Missing report field did not mention report');
  }
  recordPass('POST /service-orders/:id/report missing field', '400 esperado');

  const dbCheck = await prisma.serviceOrder.findUnique({
    where: { id: createdOrder.id },
    include: { evidences: true, reports: true },
  });
  assert(dbCheck?.status === 'FINALIZADO', 'Database status does not match finalizado after HTTP updates');
  assert(dbCheck.evidences.length === 3, 'Database evidence count mismatch after HTTP requests');
  assert(dbCheck.reports.length === 1, 'Database report count mismatch after HTTP requests');
  recordPass('Database consistency after HTTP flow', 'status/evidences/reports correctos');

  console.log('\nSUMMARY');
  for (const result of results) {
    console.log(`- ${result.status}: ${result.name}${result.details ? ` -> ${result.details}` : ''}`);
  }
  if (findings.length) {
    console.log('\nFINDINGS');
    for (const finding of findings) {
      console.log(`- ${finding}`);
    }
  }
  console.log('\nSERVICE ORDERS HTTP QA OK');
}

main()
  .catch((error) => {
    console.error('\nSERVICE ORDERS HTTP QA FAILED');
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await cleanup();
    await prisma.$disconnect();
  });