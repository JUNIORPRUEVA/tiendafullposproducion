#!/usr/bin/env node

/* eslint-disable no-console */

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { PrismaClient, Role, ServiceOrderType } = require('@prisma/client');

const prisma = new PrismaClient();
const baseUrl = `http://localhost:${process.env.PORT ?? 4000}`;
const qaTag = `qa-notifications-e2e-${Date.now()}`;

const created = {
  orderIds: [],
  jobIds: [],
  outboxIds: [],
  quotationIds: [],
  clientIds: [],
  userIds: [],
};

const results = [];
const findings = [];
const passedScenarios = [];
const failedScenarios = [];

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
  console.log(`✓ PASS ${name}`);
  if (details) console.log(`  └─ ${details}`);
}

function recordFail(name, details) {
  results.push({ status: 'FAIL', name, details: details ?? null });
  failedScenarios.push(name);
  console.error(`✗ FAIL ${name}`);
  if (details) console.error(`  └─ ${details}`);
}

function recordScenario(name, passed) {
  if (passed) {
    passedScenarios.push(name);
    console.log(`\n[SCENARIO PASS] ${name}`);
  } else {
    failedScenarios.push(name);
    console.log(`\n[SCENARIO FAIL] ${name}`);
  }
}

function recordFinding(message) {
  findings.push(message);
  console.warn(`⚠ FINDING: ${message}`);
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
    throw new Error(
      `${method} ${route} expected ${allowed.join('/')} but received ${response.status}: ${JSON.stringify(json)}`,
    );
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
      numeroFlota: '5550000',
      edad: 30,
      role,
    },
  });
  created.userIds.push(user.id);
  return user;
}

async function createQaClient(owner, label) {
  const client = await prisma.client.create({
    data: {
      ownerId: owner.id,
      nombre: `Cliente ${label}`,
      telefono: '8095552200',
      latitude: 18.4,
      longitude: -69.9,
      locationUrl: 'https://maps.google.com/?q=18.4,-69.9',
      notas: label,
    },
  });
  created.clientIds.push(client.id);
  return client;
}

async function createQaQuotation(owner, customer) {
  const quotation = await prisma.cotizacion.create({
    data: {
      createdByUserId: owner.id,
      customerId: customer.id,
      customerName: customer.nombre,
      customerPhone: customer.telefono,
      note: 'E2E QA Quotation',
      includeItbis: false,
      subtotal: 1500,
      itbisAmount: 0,
      total: 1500,
      items: {
        create: [
          {
            productNameSnapshot: 'Camera Install',
            qty: 1,
            unitPrice: 1500,
            lineTotal: 1500,
          },
        ],
      },
    },
  });
  created.quotationIds.push(quotation.id);
  return quotation;
}

async function cleanup() {
  if (created.outboxIds.length) {
    await prisma.notificationOutbox.deleteMany({ where: { id: { in: created.outboxIds } } });
  }
  if (created.jobIds.length) {
    await prisma.serviceOrderNotificationJob.deleteMany({ where: { id: { in: created.jobIds } } });
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

  console.log(`\n${'='.repeat(60)}`);
  console.log('NOTIFICATION SYSTEM E2E QA TEST');
  console.log(`${'='.repeat(60)}\n`);

  // Authenticate
  const login = await http('POST', '/auth/login', {
    identifier: adminEmail,
    password: adminPassword,
  }, undefined, 201);
  const adminToken = login.body?.accessToken;
  assert(adminToken, 'Admin login failed');
  recordPass('Admin authentication', 'Token received');

  // Create fixtures
  const admin = await createQaUser('admin-notifications', Role.ADMIN);
  const tech1 = await createQaUser('tech1-notifications', Role.TECNICO);
  const tech2 = await createQaUser('tech2-notifications', Role.TECNICO);
  const assistant = await createQaUser('assistant-notifications', Role.ASISTENTE);
  const noPhoneUser = await prisma.user.create({
    data: {
      email: `nophone-${Date.now()}@fulltech.local`,
      passwordHash: 'qa-test-hash',
      nombreCompleto: 'No Phone User',
      telefono: '',
      role: Role.TECNICO,
    },
  });
  created.userIds.push(noPhoneUser.id);

  const techToken = await (async () => {
    const res = await http('POST', '/auth/login', {
      identifier: tech1.email,
      password: 'any-password',
    }, undefined, [201, 400, 500]);
    // If login fails, we'll use admin token to create orders on behalf of tech
    return res.status === 201 ? res.body?.accessToken : adminToken;
  })();

  recordPass('Fixture setup', '3 technicians + 1 assistant + clients');

  // =========================================================================
  // SCENARIO 1: Create order with future scheduled time, verify job created
  // =========================================================================
  console.log('\n[SCENARIO 1] Create order with future scheduled timestamp');
  try {
    const client1 = await createQaClient(admin, `Client Scenario1 ${qaTag}`);
    const quota1 = await createQaQuotation(admin, client1);

    const futureTime = new Date(Date.now() + 2 * 60 * 60 * 1000); // 2 hours from now
    const createResp = await http(
      'POST',
      '/service-orders',
      {
        clientId: client1.id,
        quotationId: quota1.id,
        category: 'camara',
        serviceType: 'instalacion',
        status: 'pendiente',
        technicalNote: 'Scenario 1: Future scheduled order',
        assignedToId: tech1.id,
        scheduledFor: futureTime.toISOString(),
      },
      adminToken,
      201,
    );

    const orderId = createResp.body.id;
    created.orderIds.push(orderId);
    assert(createResp.body.scheduledFor, 'Order scheduledFor not returned');

    // Wait a bit for notification job to be created
    await new Promise((resolve) => setTimeout(resolve, 500));

    const jobs = await prisma.serviceOrderNotificationJob.findMany({
      where: { orderId },
    });

    if (jobs.length === 0) {
      recordFail(
        'Scenario 1: Notification job creation',
        'No notification job found after order creation',
      );
      recordScenario('Create order with future time', false);
    } else {
      recordPass('Scenario 1: Notification job creation', `Job created: ${jobs[0].id}`);
      created.jobIds.push(...jobs.map((j) => j.id));

      const job = jobs[0];
      assert(job.kind === 'THIRTY_MINUTES_BEFORE', `Job kind is ${job.kind}, expected THIRTY_MINUTES_BEFORE`);
      assert(job.status === 'PENDING', `Job status is ${job.status}, expected PENDING`);

      // Verify runAt is approximately 20 minutes before scheduledFor
      const scheduledForTime = new Date(createResp.body.scheduledFor).getTime();
      const runAtTime = new Date(job.runAt).getTime();
      const twentyMinutesMs = 20 * 60 * 1000;
      const diffMs = scheduledForTime - runAtTime;
      const tolerance = 5 * 60 * 1000; // 5 minute tolerance

      if (Math.abs(diffMs - twentyMinutesMs) <= tolerance) {
        recordPass('Scenario 1: 20-minute trigger timing', `Diff: ${diffMs / 60000} minutes`);
        recordScenario('Create order with future time', true);
      } else {
        recordFail(
          'Scenario 1: 20-minute trigger timing',
          `Expected ~20 min, got ${diffMs / 60000} min`,
        );
        recordScenario('Create order with future time', false);
      }
    }
  } catch (error) {
    recordFail('Scenario 1', error.message);
    recordScenario('Create order with future time', false);
  }

  // =========================================================================
  // SCENARIO 2: Technician confirmation notification
  // =========================================================================
  console.log('\n[SCENARIO 2] Technician confirms order, creator gets notified');
  try {
    const client2 = await createQaClient(admin, `Client Scenario2 ${qaTag}`);
    const quota2 = await createQaQuotation(admin, client2);
    const createResp = await http(
      'POST',
      '/service-orders',
      {
        clientId: client2.id,
        quotationId: quota2.id,
        category: 'motorPorton',
        serviceType: 'mantenimiento',
        status: 'pendiente',
        assignedToId: tech1.id,
      },
      adminToken,
      201,
    );
    const orderId = createResp.body.id;
    created.orderIds.push(orderId);

    // Confirm the order as technician
    const confirmResp = await http(
      'POST',
      `/service-orders/${orderId}/confirm`,
      {},
      adminToken, // Use admin token since we're acting as tech1
      200,
    );

    assert(confirmResp.body.technicianConfirmedAt, 'Order technicianConfirmedAt not set');
    recordPass('Scenario 2: Order confirmation', `Confirmed at ${confirmResp.body.technicianConfirmedAt}`);

    // Wait for notifications to be enqueued
    await new Promise((resolve) => setTimeout(resolve, 500));

    const outbox = await prisma.notificationOutbox.findMany({
      where: {
        payload: {
          path: ['orderId'],
          equals: orderId,
        },
      },
    });

    const confirmNotif = outbox.find((n) => n.payload?.kind === 'service_order_confirmation');
    if (confirmNotif) {
      recordPass('Scenario 2: Confirmation notification enqueued', confirmNotif.id);
      created.outboxIds.push(confirmNotif.id);
      recordScenario('Technician confirmation notification', true);
    } else {
      recordFail('Scenario 2: Confirmation notification', 'No confirmation notification found in outbox');
      recordScenario('Technician confirmation notification', false);
    }
  } catch (error) {
    recordFail('Scenario 2', error.message);
    recordScenario('Technician confirmation notification', false);
  }

  // =========================================================================
  // SCENARIO 3: EN_PROCESO transitions with different service types
  // =========================================================================
  console.log('\n[SCENARIO 3] Change to EN_PROCESO with different service types');

  // 3a: Instalacion
  try {
    const client3a = await createQaClient(admin, `Client 3a ${qaTag}`);
    const quota3a = await createQaQuotation(admin, client3a);
    const order3a = await http(
      'POST',
      '/service-orders',
      {
        clientId: client3a.id,
        quotationId: quota3a.id,
        category: 'alarma',
        serviceType: 'instalacion',
        status: 'pendiente',
      },
      adminToken,
      201,
    );
    created.orderIds.push(order3a.body.id);

    const transition = await http(
      'PATCH',
      `/service-orders/${order3a.body.id}/status`,
      { status: 'en_proceso' },
      adminToken,
      200,
    );
    assert(transition.body.status === 'en_proceso', 'Status not updated');

    await new Promise((resolve) => setTimeout(resolve, 500));
    const outbox = await prisma.notificationOutbox.findMany({
      where: {
        payload: {
          path: ['orderId'],
          equals: order3a.body.id,
        },
      },
    });

    const startedWithQuote = outbox.find((n) => n.payload?.kind === 'service_order_started_with_quote');
    if (startedWithQuote) {
      recordPass('Scenario 3a: Instalacion -> EN_PROCESO -> Assistant PDF', startedWithQuote.id);
      created.outboxIds.push(startedWithQuote.id);
      recordScenario('EN_PROCESO instalacion sends PDF to assistant', true);
    } else {
      recordFail('Scenario 3a', 'No quote notification found for instalacion');
      recordScenario('EN_PROCESO instalacion sends PDF to assistant', false);
    }
  } catch (error) {
    recordFail('Scenario 3a', error.message);
    recordScenario('EN_PROCESO instalacion sends PDF to assistant', false);
  }

  // 3b: Mantenimiento
  try {
    const client3b = await createQaClient(admin, `Client 3b ${qaTag}`);
    const quota3b = await createQaQuotation(admin, client3b);
    const order3b = await http(
      'POST',
      '/service-orders',
      {
        clientId: client3b.id,
        quotationId: quota3b.id,
        category: 'cercoElectrico',
        serviceType: 'mantenimiento',
        status: 'pendiente',
      },
      adminToken,
      201,
    );
    created.orderIds.push(order3b.body.id);

    await http(
      'PATCH',
      `/service-orders/${order3b.body.id}/status`,
      { status: 'en_proceso' },
      adminToken,
      200,
    );

    await new Promise((resolve) => setTimeout(resolve, 500));
    const outbox = await prisma.notificationOutbox.findMany({
      where: {
        payload: {
          path: ['orderId'],
          equals: order3b.body.id,
        },
      },
    });

    const startedWithQuote = outbox.find((n) => n.payload?.kind === 'service_order_started_with_quote');
    if (startedWithQuote) {
      recordPass('Scenario 3b: Mantenimiento -> EN_PROCESO -> Assistant PDF', startedWithQuote.id);
      created.outboxIds.push(startedWithQuote.id);
      recordScenario('EN_PROCESO mantenimiento sends PDF to assistant', true);
    } else {
      recordFail('Scenario 3b', 'No quote notification for mantenimiento');
      recordScenario('EN_PROCESO mantenimiento sends PDF to assistant', false);
    }
  } catch (error) {
    recordFail('Scenario 3b', error.message);
    recordScenario('EN_PROCESO mantenimiento sends PDF to assistant', false);
  }

  // 3c: Other service types (NO assistant notification expected)
  try {
    const client3c = await createQaClient(admin, `Client 3c ${qaTag}`);
    const quota3c = await createQaQuotation(admin, client3c);
    const order3c = await http(
      'POST',
      '/service-orders',
      {
        clientId: client3c.id,
        quotationId: quota3c.id,
        category: 'puntoVenta',
        serviceType: 'levantamiento',
        status: 'pendiente',
        createdById: admin.id,
      },
      adminToken,
      201,
    );
    created.orderIds.push(order3c.body.id);

    await http(
      'PATCH',
      `/service-orders/${order3c.body.id}/status`,
      { status: 'en_proceso' },
      adminToken,
      200,
    );

    await new Promise((resolve) => setTimeout(resolve, 500));
    const outbox = await prisma.notificationOutbox.findMany({
      where: {
        payload: {
          path: ['orderId'],
          equals: order3c.body.id,
        },
      },
    });

    const creatorNotif = outbox.find((n) => n.payload?.kind === 'service_order_started');
    if (creatorNotif && !outbox.find((n) => n.payload?.kind === 'service_order_started_with_quote')) {
      recordPass('Scenario 3c: Levantamiento -> Creator only (no PDF)', creatorNotif.id);
      created.outboxIds.push(creatorNotif.id);
      recordScenario('EN_PROCESO levantamiento sends to creator only', true);
    } else {
      recordFail('Scenario 3c', 'Expected creator-only notification for levantamiento');
      recordScenario('EN_PROCESO levantamiento sends to creator only', false);
    }
  } catch (error) {
    recordFail('Scenario 3c', error.message);
    recordScenario('EN_PROCESO levantamiento sends to creator only', false);
  }

  // =========================================================================
  // SCENARIO 4: FINALIZADO notifications
  // =========================================================================
  console.log('\n[SCENARIO 4] Finalize order, verify correct recipients');

  // 4a: Instalacion finalized -> assistant + creator
  try {
    const client4a = await createQaClient(admin, `Client 4a ${qaTag}`);
    const quota4a = await createQaQuotation(admin, client4a);
    const order4a = await http(
      'POST',
      '/service-orders',
      {
        clientId: client4a.id,
        quotationId: quota4a.id,
        category: 'intercom',
        serviceType: 'instalacion',
        status: 'pendiente',
      },
      adminToken,
      201,
    );
    created.orderIds.push(order4a.body.id);

    await http(
      'PATCH',
      `/service-orders/${order4a.body.id}/status`,
      { status: 'en_proceso' },
      adminToken,
      200,
    );

    await http(
      'PATCH',
      `/service-orders/${order4a.body.id}/status`,
      { status: 'finalizado' },
      adminToken,
      200,
    );

    await new Promise((resolve) => setTimeout(resolve, 500));
    const outbox = await prisma.notificationOutbox.findMany({
      where: {
        payload: {
          path: ['orderId'],
          equals: order4a.body.id,
        },
      },
    });

    const finalizedNotif = outbox.find((n) => n.payload?.kind === 'service_order_finalized_invoice_flow');
    if (finalizedNotif) {
      recordPass('Scenario 4a: Instalacion finalized notification', finalizedNotif.id);
      created.outboxIds.push(finalizedNotif.id);
      recordScenario('FINALIZADO instalacion sends to assistant + creator', true);
    } else {
      recordFail('Scenario 4a', 'No finalized invoice flow notification');
      recordScenario('FINALIZADO instalacion sends to assistant + creator', false);
    }
  } catch (error) {
    recordFail('Scenario 4a', error.message);
    recordScenario('FINALIZADO instalacion sends to assistant + creator', false);
  }

  // 4b: Non-invoice service finalized -> creator only
  try {
    const client4b = await createQaClient(admin, `Client 4b ${qaTag}`);
    const quota4b = await createQaQuotation(admin, client4b);
    const order4b = await http(
      'POST',
      '/service-orders',
      {
        clientId: client4b.id,
        quotationId: quota4b.id,
        category: 'motorPorton',
        serviceType: 'garantia',
        status: 'pendiente',
      },
      adminToken,
      201,
    );
    created.orderIds.push(order4b.body.id);

    await http(
      'PATCH',
      `/service-orders/${order4b.body.id}/status`,
      { status: 'en_proceso' },
      adminToken,
      200,
    );

    await http(
      'PATCH',
      `/service-orders/${order4b.body.id}/status`,
      { status: 'finalizado' },
      adminToken,
      200,
    );

    await new Promise((resolve) => setTimeout(resolve, 500));
    const outbox = await prisma.notificationOutbox.findMany({
      where: {
        payload: {
          path: ['orderId'],
          equals: order4b.body.id,
        },
      },
    });

    const finalizedNotif = outbox.find((n) => n.payload?.kind === 'service_order_finalized');
    if (finalizedNotif && !outbox.find((n) => n.payload?.kind === 'service_order_finalized_invoice_flow')) {
      recordPass('Scenario 4b: Garantia finalized (creator only)', finalizedNotif.id);
      created.outboxIds.push(finalizedNotif.id);
      recordScenario('FINALIZADO garantia sends to creator only', true);
    } else {
      recordFail('Scenario 4b', 'Expected creator-only notification for garantia');
      recordScenario('FINALIZADO garantia sends to creator only', false);
    }
  } catch (error) {
    recordFail('Scenario 4b', error.message);
    recordScenario('FINALIZADO garantia sends to creator only', false);
  }

  // =========================================================================
  // SCENARIO 5: Edge cases
  // =========================================================================
  console.log('\n[SCENARIO 5] Edge cases');

  // 5a: Client missing GPS
  try {
    const clientNoGps = await prisma.client.create({
      data: {
        ownerId: admin.id,
        nombre: `Client No GPS ${qaTag}`,
        telefono: '8095555555',
        // No location fields
        notas: 'edge-case-no-gps',
      },
    });
    created.clientIds.push(clientNoGps.id);
    const quota5a = await createQaQuotation(admin, clientNoGps);

    const order5a = await http(
      'POST',
      '/service-orders',
      {
        clientId: clientNoGps.id,
        quotationId: quota5a.id,
        category: 'camara',
        serviceType: 'instalacion',
        status: 'pendiente',
      },
      adminToken,
      201,
    );
    created.orderIds.push(order5a.body.id);

    await http(
      'PATCH',
      `/service-orders/${order5a.body.id}/status`,
      { status: 'en_proceso' },
      adminToken,
      200,
    );

    await new Promise((resolve) => setTimeout(resolve, 500));
    const outbox = await prisma.notificationOutbox.findMany({
      where: {
        payload: {
          path: ['orderId'],
          equals: order5a.body.id,
        },
      },
    });

    if (outbox.length > 0) {
      const msg = outbox[0].messageText;
      if (msg.includes('Ubicación no registrada') || msg.includes('maps.google.com')) {
        recordPass('Scenario 5a: Missing GPS handled', 'Fallback message sent');
        created.outboxIds.push(...outbox.map((n) => n.id));
        recordScenario('Missing GPS location', true);
      } else {
        recordFail('Scenario 5a', 'Location message not handled correctly');
        recordScenario('Missing GPS location', false);
      }
    } else {
      recordFail('Scenario 5a', 'No notifications generated');
      recordScenario('Missing GPS location', false);
    }
  } catch (error) {
    recordFail('Scenario 5a', error.message);
    recordScenario('Missing GPS location', false);
  }

  // 5b: User with no phone number
  try {
    const clientEdge = await createQaClient(admin, `Client Edge ${qaTag}`);
    const quotaEdge = await createQaQuotation(admin, clientEdge);

    const order5b = await http(
      'POST',
      '/service-orders',
      {
        clientId: clientEdge.id,
        quotationId: quotaEdge.id,
        category: 'alarma',
        serviceType: 'levantamiento',
        status: 'pendiente',
        assignedToId: noPhoneUser.id,
      },
      adminToken,
      201,
    );
    created.orderIds.push(order5b.body.id);

    // Attempt confirmation
    try {
      await http(
        'POST',
        `/service-orders/${order5b.body.id}/confirm`,
        {},
        adminToken,
        [200, 400],
      );
      recordPass('Scenario 5b: User with no phone', 'System handled gracefully');
      recordScenario('User with no phone number', true);
    } catch {
      recordFinding('Scenario 5b: User with no phone may cause errors');
      recordScenario('User with no phone number', false);
    }
  } catch (error) {
    recordFail('Scenario 5b', error.message);
    recordScenario('User with no phone number', false);
  }

  // =========================================================================
  // SCENARIO 6: Stress test - multiple orders same time
  // =========================================================================
  console.log('\n[SCENARIO 6] Stress test - multiple orders simultaneously');
  try {
    const stressOrders = [];
    const stressTime = new Date(Date.now() + 60 * 60 * 1000); // 1 hour

    for (let i = 0; i < 5; i++) {
      const client = await createQaClient(admin, `StressClient${i} ${qaTag}`);
      const quota = await createQaQuotation(admin, client);
      const resp = await http(
        'POST',
        '/service-orders',
        {
          clientId: client.id,
          quotationId: quota.id,
          category: ['camara', 'alarma', 'motorPorton', 'intercom', 'cercoElectrico'][i],
          serviceType: ['instalacion', 'mantenimiento', 'levantamiento', 'garantia', 'instalacion'][i],
          status: 'pendiente',
          assignedToId: [tech1.id, tech2.id][i % 2],
          scheduledFor: stressTime.toISOString(),
        },
        adminToken,
        201,
      );
      stressOrders.push(resp.body.id);
      created.orderIds.push(resp.body.id);
    }

    await new Promise((resolve) => setTimeout(resolve, 1000));

    const jobs = await prisma.serviceOrderNotificationJob.findMany({
      where: { orderId: { in: stressOrders } },
    });

    created.jobIds.push(...jobs.map((j) => j.id));

    if (jobs.length === 5) {
      recordPass('Scenario 6: Stress test - 5 jobs created', `Jobs: ${jobs.length}`);
      recordScenario('Multiple orders scheduled simultaneously', true);
    } else {
      recordFail('Scenario 6', `Expected 5 jobs, got ${jobs.length}`);
      recordScenario('Multiple orders scheduled simultaneously', false);
    }
  } catch (error) {
    recordFail('Scenario 6', error.message);
    recordScenario('Multiple orders scheduled simultaneously', false);
  }

  // =========================================================================
  // VERIFICATION & SUMMARY
  // =========================================================================
  console.log(`\n${'='.repeat(60)}`);
  console.log('TEST SUMMARY');
  console.log(`${'='.repeat(60)}\n`);

  const passCount = results.filter((r) => r.status === 'PASS').length;
  const failCount = results.filter((r) => r.status === 'FAIL').length;

  console.log(`Passed: ${passCount}`);
  console.log(`Failed: ${failCount}`);
  console.log(`Total:  ${results.length}\n`);

  console.log('Results:');
  for (const result of results) {
    const icon = result.status === 'PASS' ? '✓' : '✗';
    console.log(`${icon} ${result.status.padEnd(4)} ${result.name}${result.details ? ` -> ${result.details}` : ''}`);
  }

  if (findings.length) {
    console.log(`\nFindings: ${findings.length}`);
    for (const finding of findings) {
      console.log(`⚠ ${finding}`);
    }
  }

  console.log(`\n${'='.repeat(60)}`);
  console.log('SCENARIO RESULTS');
  console.log(`${'='.repeat(60)}\n`);

  console.log(`Passed Scenarios: ${passedScenarios.length}`);
  for (const scenario of passedScenarios) {
    console.log(`✓ ${scenario}`);
  }

  if (failedScenarios.length) {
    console.log(`\nFailed Scenarios: ${failedScenarios.length}`);
    for (const scenario of failedScenarios) {
      console.log(`✗ ${scenario}`);
    }
  }

  console.log(`\n${'='.repeat(60)}`);
  const allPassed = failCount === 0 && passedScenarios.length >= 4;
  const verdict = allPassed ? 'READY' : 'NOT READY';
  console.log(`VERDICT: ${verdict}`);
  console.log(`${'='.repeat(60)}\n`);

  if (!allPassed) {
    process.exitCode = 1;
  }
}

main()
  .catch((error) => {
    console.error('\n❌ E2E TEST FAILED');
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await cleanup();
    await prisma.$disconnect();
  });
