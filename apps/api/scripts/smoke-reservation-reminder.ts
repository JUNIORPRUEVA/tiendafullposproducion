/* eslint-disable no-console */

import { PrismaService } from '../src/prisma/prisma.service';
import { EvolutionWhatsAppService } from '../src/notifications/evolution-whatsapp.service';
import { NotificationsService } from '../src/notifications/notifications.service';

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
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
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

function iso(d: Date) {
  return d.toISOString();
}

async function main() {
  // Use mock send mode so we can exercise outbox dispatch + chaining locally.
  process.env.NOTIFICATIONS_MOCK_SUCCESS = process.env.NOTIFICATIONS_MOCK_SUCCESS ?? '1';

  await waitForHealth();
  console.log('health ok');

  const login = await http('POST', '/auth/login', {
    identifier: adminEmail,
    password: adminPassword,
  });
  const token = login.accessToken as string;
  if (!token) throw new Error('Missing accessToken');
  console.log('login ok');

  const me = await http('GET', '/users/me', undefined, token);
  if (!me?.id) throw new Error('Missing /users/me id');

  const fleetNumber = '8090000099';
  await http('PATCH', `/users/${me.id}`, { numeroFlota: fleetNumber }, token);
  console.log('numeroFlota set on admin', fleetNumber);

  const clientPhone = '8090000098';
  const client = await http(
    'POST',
    '/clients',
    { nombre: `Cliente Reserva Smoke ${Date.now()}`, telefono: clientPhone },
    token,
  );
  if (!client?.id) throw new Error('Client create missing id');
  console.log('client created', client.id);

  const service = await http(
    'POST',
    '/services',
    {
      customerId: client.id,
      serviceType: 'other',
      category: 'General',
      title: `Reserva Smoke ${Date.now()}`,
      description: 'Reserva creada por smoke test',
      orderType: 'reserva',
    },
    token,
  );
  if (!service?.id) throw new Error('Service create missing id');
  console.log('service created', service.id);

  // Make it due immediately: scheduledStart in the past.
  const now = new Date();
  const start = new Date(now.getTime() - 2 * 60 * 1000);
  const end = new Date(start.getTime() + 60 * 60 * 1000);

  await http(
    'PATCH',
    `/services/${service.id}/schedule`,
    {
      scheduledStart: iso(start),
      scheduledEnd: iso(end),
      message: 'Agendado por smoke test',
    },
    token,
  );
  console.log('service scheduled', iso(start));

  const prisma = new PrismaService();
  await prisma.$connect();

  try {
    const evolution = new EvolutionWhatsAppService(prisma);
    const notifications = new NotificationsService(prisma, evolution);

    const initialKey = `reservation_reminder_initial:${service.id}`;

    const initialRowBefore = await prisma.notificationOutbox.findUnique({
      where: { dedupeKey: initialKey },
    });
    if (!initialRowBefore) {
      throw new Error(`Expected initial outbox row missing: ${initialKey}`);
    }
    console.log('initial outbox row exists', { status: initialRowBefore.status, nextAttemptAt: initialRowBefore.nextAttemptAt });

    await notifications.processOutboxBatch(25);

    const initialRowAfter = await prisma.notificationOutbox.findUnique({
      where: { dedupeKey: initialKey },
    });
    if (!initialRowAfter) throw new Error('Initial row disappeared unexpectedly');
    if (initialRowAfter.status !== 'SENT') {
      throw new Error(`Expected initial row status SENT, got ${initialRowAfter.status}`);
    }
    console.log('initial reminder SENT');

    const hourly = await prisma.notificationOutbox.findFirst({
      where: {
        dedupeKey: { startsWith: `reservation_reminder_hourly:${service.id}:` },
      },
      orderBy: { nextAttemptAt: 'asc' },
    });

    if (!hourly) {
      throw new Error('Expected hourly follow-up outbox row to be queued, but none found');
    }

    console.log('hourly follow-up queued', {
      status: hourly.status,
      nextAttemptAt: hourly.nextAttemptAt,
      dedupeKey: hourly.dedupeKey,
      toNumber: hourly.toNumber,
    });

    if (hourly.toNumber.replace(/[^0-9]/g, '') !== fleetNumber) {
      throw new Error(`Expected hourly reminder to be sent to fleet numeroFlota=${fleetNumber}, got ${hourly.toNumber}`);
    }

    console.log('SMOKE RESERVATION REMINDER OK');
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
