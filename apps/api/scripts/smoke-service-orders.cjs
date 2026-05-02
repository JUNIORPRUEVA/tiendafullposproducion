#!/usr/bin/env node

/* eslint-disable no-console */

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const {
  PrismaClient,
  Role,
  ServiceOrderCategory,
  ServiceOrderType,
  ServiceOrderStatus,
  ServiceEvidenceType,
} = require('@prisma/client');

const prisma = new PrismaClient();
const qaTag = `qa-service-orders-${Date.now()}`;

const created = {
  evidenceIds: [],
  reportIds: [],
  orderIds: [],
  quotationIds: [],
  clientIds: [],
  userIds: [],
};

const results = [];
const bugs = [];

function randomUuid() {
  return crypto.randomUUID();
}

function test(name, details) {
  results.push({ name, status: 'PASS', details });
  console.log(`PASS ${name}`);
  if (details) console.log(`  ${details}`);
}

function fail(name, error) {
  results.push({ name, status: 'FAIL', details: error.message });
  console.error(`FAIL ${name}`);
  console.error(`  ${error.message}`);
  throw error;
}

function bug(summary) {
  bugs.push(summary);
  console.warn(`BUG ${summary}`);
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function assertBackendUsesLastStatusChangedAtFilter() {
  const serviceFile = path.resolve(__dirname, '../src/service-orders/service-orders.service.ts');
  const source = fs.readFileSync(serviceFile, 'utf8');

  assert(
    source.includes('where.lastStatusChangedAt = {'),
    'buildListWhere no usa lastStatusChangedAt para filtrar por fecha',
  );
  assert(
    !source.includes('where.createdAt = {'),
    'buildListWhere parece filtrar por createdAt en lugar de lastStatusChangedAt',
  );
}

function assertBackendTransitionsIncludePause() {
  const constantsFile = path.resolve(__dirname, '../src/service-orders/service-orders.constants.ts');
  const source = fs.readFileSync(constantsFile, 'utf8');

  assert(
    source.includes("en_proceso: ['en_pausa', 'finalizado', 'pospuesta', 'cancelado']"),
    'No existe transición en_proceso -> en_pausa en constantes backend',
  );
  assert(
    source.includes("en_pausa: ['en_proceso', 'pospuesta', 'cancelado']"),
    'No existe transición en_pausa -> en_proceso en constantes backend',
  );
}

function toIsoDate(value) {
  return value.toISOString();
}

function statusToDbValue(status) {
  if (status == null) return null;
  const mapping = {
    [ServiceOrderStatus.PENDIENTE]: 'pendiente',
    [ServiceOrderStatus.EN_PROCESO]: 'en_proceso',
    [ServiceOrderStatus.EN_PAUSA]: 'en_pausa',
    [ServiceOrderStatus.POSPUESTA]: 'pospuesta',
    [ServiceOrderStatus.FINALIZADO]: 'finalizado',
    [ServiceOrderStatus.CANCELADO]: 'cancelado',
  };
  const value = mapping[status];
  assert(value, `Estado no mapeado a DB: ${status}`);
  return value;
}

async function listOrdersLikeOperationsFilter({ statuses, from, to }) {
  const requestedStatuses = Array.isArray(statuses) && statuses.length > 0
    ? statuses
    : [ServiceOrderStatus.PENDIENTE, ServiceOrderStatus.EN_PROCESO, ServiceOrderStatus.EN_PAUSA];

  const where = {
    status: { in: requestedStatuses },
    ...(from || to
      ? {
          lastStatusChangedAt: {
            ...(from ? { gte: from } : {}),
            ...(to ? { lte: to } : {}),
          },
        }
      : {}),
  };

  return prisma.serviceOrder.findMany({
    where,
    orderBy: [{ lastStatusChangedAt: 'desc' }, { createdAt: 'desc' }],
    select: {
      id: true,
      status: true,
      createdAt: true,
      lastStatusChangedAt: true,
    },
  });
}

async function getStatusHistoryOptionalColumns() {
  const rows = await prisma.$queryRawUnsafe(`
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'service_order_status_history'
      AND column_name IN ('changed_by_user_name', 'created_at')
  `);

  const names = new Set(rows.map((row) => String(row.column_name || '').trim()));
  return {
    hasChangedByUserName: names.has('changed_by_user_name'),
    hasCreatedAt: names.has('created_at'),
  };
}

async function insertStatusHistoryRow({
  supports,
  serviceOrderId,
  previousStatus,
  nextStatus,
  changedAt,
  changedByUserId,
  changedByUserName,
  note,
}) {
  const cols = [];
  const placeholders = [];
  const params = [];

  function push(col, value, cast) {
    params.push(value);
    const index = params.length;
    cols.push(`"${col}"`);
    placeholders.push(cast ? `$${index}::${cast}` : `$${index}`);
  }

  push('service_order_id', serviceOrderId, 'uuid');
  push('previous_status', statusToDbValue(previousStatus), 'service_order_status');
  push('next_status', statusToDbValue(nextStatus), 'service_order_status');
  push('changed_at', changedAt, 'timestamp');
  push('changed_by_user_id', changedByUserId, 'uuid');
  push('note', note, 'text');

  if (supports.hasChangedByUserName) {
    push('changed_by_user_name', changedByUserName, 'text');
  }
  if (supports.hasCreatedAt) {
    push('created_at', changedAt, 'timestamp');
  }

  const sql = `
    INSERT INTO service_order_status_history (${cols.join(', ')})
    VALUES (${placeholders.join(', ')})
  `;
  await prisma.$executeRawUnsafe(sql, ...params);
}

async function applyStatusChangeWithHistory({
  supports,
  orderId,
  previousStatus,
  nextStatus,
  changedAt,
  changedByUserId,
  changedByUserName,
}) {
  await prisma.serviceOrder.update({
    where: { id: orderId },
    data: {
      status: nextStatus,
      lastStatusChangedAt: changedAt,
      lastStatusChangedByUserId: changedByUserId,
      finalizedAt: nextStatus === ServiceOrderStatus.FINALIZADO ? changedAt : null,
    },
  });

  await insertStatusHistoryRow({
    supports,
    serviceOrderId: orderId,
    previousStatus,
    nextStatus,
    changedAt,
    changedByUserId,
    changedByUserName,
    note: `QA transition ${previousStatus ?? 'null'} -> ${nextStatus}`,
  });
}

async function runStatusDateFilterRegressionCase(fixture) {
  const supports = await getStatusHistoryOptionalColumns();
  assertBackendUsesLastStatusChangedAtFilter();
  assertBackendTransitionsIncludePause();

  const createdAtOld = new Date('2026-10-01T09:00:00.000Z');
  const inProgressAt = new Date('2026-10-02T10:00:00.000Z');
  const pausedAt = new Date('2026-10-05T11:30:00.000Z');
  const resumedAt = new Date('2026-10-07T14:45:00.000Z');
  const finalizedAt = new Date('2026-10-10T16:00:00.000Z');

  const order = await prisma.serviceOrder.create({
    data: {
      clientId: fixture.client.id,
      quotationId: fixture.quotation.id,
      category: ServiceOrderCategory.CAMARA,
      serviceType: ServiceOrderType.MANTENIMIENTO,
      status: ServiceOrderStatus.PENDIENTE,
      createdById: fixture.owner.id,
      assignedToId: fixture.technician.id,
      technicalNote: 'status-date-filter-uses-last-status-changed-at',
      extraRequirements: qaTag,
      lastStatusChangedAt: createdAtOld,
      lastStatusChangedByUserId: fixture.owner.id,
      createdAt: createdAtOld,
    },
  });
  created.orderIds.push(order.id);

  await insertStatusHistoryRow({
    supports,
    serviceOrderId: order.id,
    previousStatus: null,
    nextStatus: ServiceOrderStatus.PENDIENTE,
    changedAt: createdAtOld,
    changedByUserId: fixture.owner.id,
    changedByUserName: fixture.owner.nombreCompleto,
    note: 'Estado inicial QA',
  });

  await applyStatusChangeWithHistory({
    supports,
    orderId: order.id,
    previousStatus: ServiceOrderStatus.PENDIENTE,
    nextStatus: ServiceOrderStatus.EN_PROCESO,
    changedAt: inProgressAt,
    changedByUserId: fixture.technician.id,
    changedByUserName: fixture.technician.nombreCompleto,
  });

  await applyStatusChangeWithHistory({
    supports,
    orderId: order.id,
    previousStatus: ServiceOrderStatus.EN_PROCESO,
    nextStatus: ServiceOrderStatus.EN_PAUSA,
    changedAt: pausedAt,
    changedByUserId: fixture.technician.id,
    changedByUserName: fixture.technician.nombreCompleto,
  });

  await applyStatusChangeWithHistory({
    supports,
    orderId: order.id,
    previousStatus: ServiceOrderStatus.EN_PAUSA,
    nextStatus: ServiceOrderStatus.EN_PROCESO,
    changedAt: resumedAt,
    changedByUserId: fixture.technician.id,
    changedByUserName: fixture.technician.nombreCompleto,
  });

  await applyStatusChangeWithHistory({
    supports,
    orderId: order.id,
    previousStatus: ServiceOrderStatus.EN_PROCESO,
    nextStatus: ServiceOrderStatus.FINALIZADO,
    changedAt: finalizedAt,
    changedByUserId: fixture.technician.id,
    changedByUserName: fixture.technician.nombreCompleto,
  });

  const refreshedOrder = await prisma.serviceOrder.findUniqueOrThrow({
    where: { id: order.id },
    select: {
      id: true,
      status: true,
      createdAt: true,
      lastStatusChangedAt: true,
    },
  });

  assert(
    toIsoDate(refreshedOrder.lastStatusChangedAt) === toIsoDate(finalizedAt),
    `lastStatusChangedAt esperado ${toIsoDate(finalizedAt)} pero se obtuvo ${toIsoDate(refreshedOrder.lastStatusChangedAt)}`,
  );

  const history = await prisma.serviceOrderStatusHistory.findMany({
    where: { serviceOrderId: order.id },
    orderBy: { changedAt: 'asc' },
    select: {
      previousStatus: true,
      nextStatus: true,
      changedAt: true,
      changedByUserId: true,
    },
  });

  assert(history.length >= 5, `Historial insuficiente. Esperado >= 5, actual ${history.length}`);
  assert(
    history.every((item) => item.nextStatus && item.changedAt && item.changedByUserId),
    'Historial incompleto: falta nextStatus, changedAt o changedByUserId',
  );
  assert(
    history.some((item) => item.previousStatus === ServiceOrderStatus.EN_PROCESO && item.nextStatus === ServiceOrderStatus.EN_PAUSA),
    'No existe transición EN_PROCESO -> EN_PAUSA en historial',
  );
  assert(
    history.some((item) => item.previousStatus === ServiceOrderStatus.EN_PAUSA && item.nextStatus === ServiceOrderStatus.EN_PROCESO),
    'No existe transición EN_PAUSA -> EN_PROCESO en historial',
  );

  const finalDayStart = new Date('2026-10-10T00:00:00.000Z');
  const finalDayEnd = new Date('2026-10-10T23:59:59.999Z');
  const createdDayStart = new Date('2026-10-01T00:00:00.000Z');
  const createdDayEnd = new Date('2026-10-01T23:59:59.999Z');

  const defaultFinalDay = await listOrdersLikeOperationsFilter({
    from: finalDayStart,
    to: finalDayEnd,
  });
  assert(
    !defaultFinalDay.some((item) => item.id === order.id),
    'Orden finalizada apareció en filtro por defecto (debe excluir FINALIZADO)',
  );

  const explicitFinalizedFinalDay = await listOrdersLikeOperationsFilter({
    statuses: [ServiceOrderStatus.FINALIZADO],
    from: finalDayStart,
    to: finalDayEnd,
  });
  assert(
    explicitFinalizedFinalDay.some((item) => item.id === order.id),
    'Orden finalizada no apareció al filtrar explícitamente FINALIZADO por fecha de último estado',
  );

  const explicitFinalizedCreatedDay = await listOrdersLikeOperationsFilter({
    statuses: [ServiceOrderStatus.FINALIZADO],
    from: createdDayStart,
    to: createdDayEnd,
  });
  assert(
    !explicitFinalizedCreatedDay.some((item) => item.id === order.id),
    'Orden apareció por fecha de creación aunque su último estado es de otra fecha',
  );

  test(
    'status-date-filter-uses-last-status-changed-at',
    `order=${order.id} createdAt=${toIsoDate(refreshedOrder.createdAt)} lastStatusChangedAt=${toIsoDate(refreshedOrder.lastStatusChangedAt)}`,
  );
  console.log('✅ status-date-filter-uses-last-status-changed-at OK');
}

async function expectReject(name, fn, validator) {
  let rejected = false;
  try {
    await fn();
  } catch (error) {
    rejected = true;
    if (validator) validator(error);
    test(name, error.message);
  }

  if (!rejected) {
    fail(name, new Error('Expected operation to fail but it succeeded'));
  }
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

async function createFixtureData() {
  const owner = await createQaUser('service-orders-owner', Role.ADMIN);
  const technician = await createQaUser('service-orders-tech', Role.TECNICO);

  const client = await prisma.client.create({
    data: {
      ownerId: owner.id,
      nombre: `Cliente ${qaTag}`,
      telefono: '8095551000',
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
  const fixture = await createFixtureData();

  await runStatusDateFilterRegressionCase(fixture);

  const createdOrder = await prisma.serviceOrder.create({
    data: {
      clientId: fixture.client.id,
      quotationId: fixture.quotation.id,
      category: ServiceOrderCategory.CAMARA,
      serviceType: ServiceOrderType.INSTALACION,
      status: ServiceOrderStatus.PENDIENTE,
      technicalNote: 'Initial technical note',
      extraRequirements: 'Access ladder required',
      createdById: fixture.owner.id,
      assignedToId: fixture.technician.id,
    },
  });
  created.orderIds.push(createdOrder.id);

  const dbRows = await prisma.$queryRawUnsafe(
    'SELECT id, client_id, quotation_id, category::text AS category, service_type::text AS service_type, status::text AS status, created_by, assigned_to FROM service_orders WHERE id = $1::uuid',
    createdOrder.id,
  );
  const storedRow = dbRows[0];
  assert(storedRow, 'Created service order was not found in database');
  assert(storedRow.client_id === fixture.client.id, 'client_id was not stored correctly');
  assert(storedRow.quotation_id === fixture.quotation.id, 'quotation_id was not stored correctly');
  assert(storedRow.category === 'camara', 'category enum value was not stored correctly');
  assert(storedRow.service_type === 'instalacion', 'service_type enum value was not stored correctly');
  assert(storedRow.status === 'pendiente', 'status enum value was not stored correctly');
  test('Create service order', createdOrder.id);

  await expectReject(
    'Required fields enforced on create',
    async () => {
      await prisma.serviceOrder.create({
        data: {
          quotationId: fixture.quotation.id,
          category: ServiceOrderCategory.CAMARA,
          serviceType: ServiceOrderType.INSTALACION,
          status: ServiceOrderStatus.PENDIENTE,
          createdById: fixture.owner.id,
        },
      });
    },
    (error) => {
      assert(/Argument `client` is missing|clientId/i.test(error.message), 'Missing required field error did not mention clientId');
    },
  );

  await expectReject(
    'Invalid category enum rejected',
    async () => {
      await prisma.serviceOrder.create({
        data: {
          clientId: fixture.client.id,
          quotationId: fixture.quotation.id,
          category: 'INVALID_CATEGORY',
          serviceType: ServiceOrderType.INSTALACION,
          status: ServiceOrderStatus.PENDIENTE,
          createdById: fixture.owner.id,
        },
      });
    },
    (error) => {
      assert(/invalid.*category|Value 'INVALID_CATEGORY' not found|Expected ServiceOrderCategory/i.test(error.message), 'Invalid category error message was not clear');
    },
  );

  await expectReject(
    'Invalid service_type enum rejected',
    async () => {
      await prisma.serviceOrder.create({
        data: {
          clientId: fixture.client.id,
          quotationId: fixture.quotation.id,
          category: ServiceOrderCategory.CAMARA,
          serviceType: 'INVALID_TYPE',
          status: ServiceOrderStatus.PENDIENTE,
          createdById: fixture.owner.id,
        },
      });
    },
  );

  await expectReject(
    'Invalid status enum rejected on create',
    async () => {
      await prisma.serviceOrder.create({
        data: {
          clientId: fixture.client.id,
          quotationId: fixture.quotation.id,
          category: ServiceOrderCategory.CAMARA,
          serviceType: ServiceOrderType.INSTALACION,
          status: 'INVALID_STATUS',
          createdById: fixture.owner.id,
        },
      });
    },
  );

  const allOrders = await prisma.serviceOrder.findMany({
    where: { id: { in: created.orderIds } },
    orderBy: { createdAt: 'desc' },
  });
  assert(Array.isArray(allOrders), 'Get all orders did not return a list');
  assert(allOrders.some((row) => row.id === createdOrder.id), 'Created order not found in get all list');
  test('Get all service orders', `rows=${allOrders.length}`);

  const textEvidence = await prisma.serviceEvidence.create({
    data: {
      serviceOrderId: createdOrder.id,
      type: ServiceEvidenceType.REFERENCIA_TEXTO,
      content: 'Texto de evidencia QA',
      createdById: fixture.owner.id,
    },
  });
  created.evidenceIds.push(textEvidence.id);

  const imageEvidence = await prisma.serviceEvidence.create({
    data: {
      serviceOrderId: createdOrder.id,
      type: ServiceEvidenceType.REFERENCIA_IMAGEN,
      content: 'https://example.com/mock-image.jpg',
      createdById: fixture.owner.id,
    },
  });
  created.evidenceIds.push(imageEvidence.id);

  const videoEvidence = await prisma.serviceEvidence.create({
    data: {
      serviceOrderId: createdOrder.id,
      type: ServiceEvidenceType.EVIDENCIA_VIDEO,
      content: 'https://example.com/mock-video.mp4',
      createdById: fixture.owner.id,
    },
  });
  created.evidenceIds.push(videoEvidence.id);

  const report = await prisma.serviceReport.create({
    data: {
      serviceOrderId: createdOrder.id,
      report: 'Reporte tecnico QA',
      createdById: fixture.owner.id,
    },
  });
  created.reportIds.push(report.id);
  test('Add evidences and report', `evidences=3 reports=1`);

  const orderWithRelations = await prisma.serviceOrder.findUnique({
    where: { id: createdOrder.id },
    include: {
      evidences: { orderBy: { createdAt: 'asc' } },
      reports: { orderBy: { createdAt: 'asc' } },
    },
  });
  assert(orderWithRelations, 'Get order by id returned null');
  assert(orderWithRelations.evidences.length === 3, 'Expected 3 evidences on relation include');
  assert(orderWithRelations.reports.length === 1, 'Expected 1 report on relation include');
  assert(orderWithRelations.evidences.every((item) => item.serviceOrderId === createdOrder.id), 'Evidence relation linked to wrong order');
  assert(orderWithRelations.reports[0].serviceOrderId === createdOrder.id, 'Report relation linked to wrong order');
  test('Get service order by id with relations', createdOrder.id);

  const inProgressOrder = await prisma.serviceOrder.update({
    where: { id: createdOrder.id },
    data: { status: ServiceOrderStatus.EN_PROCESO },
  });
  assert(inProgressOrder.status === ServiceOrderStatus.EN_PROCESO, 'Status did not update to EN_PROCESO');

  const finalizedOrder = await prisma.serviceOrder.update({
    where: { id: createdOrder.id },
    data: { status: ServiceOrderStatus.FINALIZADO },
  });
  assert(finalizedOrder.status === ServiceOrderStatus.FINALIZADO, 'Status did not update to FINALIZADO');
  test('Update status pendiente -> en_proceso -> finalizado', finalizedOrder.status);

  await expectReject(
    'Invalid status rejected on update',
    async () => {
      await prisma.serviceOrder.update({
        where: { id: createdOrder.id },
        data: { status: 'NOT_A_STATUS' },
      });
    },
  );

  const clonedOrder = await prisma.serviceOrder.create({
    data: {
      clientId: createdOrder.clientId,
      quotationId: createdOrder.quotationId,
      category: createdOrder.category,
      serviceType: ServiceOrderType.GARANTIA,
      status: ServiceOrderStatus.PENDIENTE,
      parentOrderId: createdOrder.id,
      createdById: fixture.owner.id,
      assignedToId: fixture.technician.id,
      technicalNote: 'Cloned from original order',
    },
  });
  created.orderIds.push(clonedOrder.id);

  assert(clonedOrder.clientId === createdOrder.clientId, 'Clone did not copy client_id');
  assert(clonedOrder.quotationId === createdOrder.quotationId, 'Clone did not copy quotation_id');
  assert(clonedOrder.parentOrderId === createdOrder.id, 'Clone did not set parent_order_id');
  assert(clonedOrder.serviceType === ServiceOrderType.GARANTIA, 'Clone did not accept new service_type');

  const updatedClone = await prisma.serviceOrder.update({
    where: { id: clonedOrder.id },
    data: { status: ServiceOrderStatus.CANCELADO },
  });
  const originalAfterClone = await prisma.serviceOrder.findUnique({ where: { id: createdOrder.id } });
  assert(updatedClone.status === ServiceOrderStatus.CANCELADO, 'Clone did not update independently');
  assert(originalAfterClone.status === ServiceOrderStatus.FINALIZADO, 'Original order changed when clone was updated');
  test('Clone order', clonedOrder.id);

  const missingOrder = await prisma.serviceOrder.findUnique({ where: { id: randomUuid() } });
  assert(missingOrder === null, 'Non-existing get by id should return null');
  test('Non-existing order get by id', 'null returned as expected');

  await expectReject(
    'Non-existing client_id rejected',
    async () => {
      await prisma.serviceOrder.create({
        data: {
          clientId: randomUuid(),
          quotationId: fixture.quotation.id,
          category: ServiceOrderCategory.CAMARA,
          serviceType: ServiceOrderType.INSTALACION,
          status: ServiceOrderStatus.PENDIENTE,
          createdById: fixture.owner.id,
        },
      });
    },
    (error) => {
      assert(/Foreign key constraint|P2003/i.test(error.message), 'Expected foreign key rejection for missing client_id');
    },
  );

  await expectReject(
    'Non-existing quotation_id rejected',
    async () => {
      await prisma.serviceOrder.create({
        data: {
          clientId: fixture.client.id,
          quotationId: randomUuid(),
          category: ServiceOrderCategory.CAMARA,
          serviceType: ServiceOrderType.INSTALACION,
          status: ServiceOrderStatus.PENDIENTE,
          createdById: fixture.owner.id,
        },
      });
    },
    (error) => {
      assert(/Foreign key constraint|P2003/i.test(error.message), 'Expected foreign key rejection for missing quotation_id');
    },
  );

  await expectReject(
    'Non-existing parent_order_id rejected',
    async () => {
      await prisma.serviceOrder.create({
        data: {
          clientId: fixture.client.id,
          quotationId: fixture.quotation.id,
          category: ServiceOrderCategory.CAMARA,
          serviceType: ServiceOrderType.GARANTIA,
          status: ServiceOrderStatus.PENDIENTE,
          parentOrderId: randomUuid(),
          createdById: fixture.owner.id,
        },
      });
    },
    (error) => {
      assert(/Foreign key constraint|P2003/i.test(error.message), 'Expected foreign key rejection for missing parent_order_id');
    },
  );

  await expectReject(
    'Non-existing service_order_id rejected for evidence',
    async () => {
      await prisma.serviceEvidence.create({
        data: {
          serviceOrderId: randomUuid(),
          type: ServiceEvidenceType.REFERENCIA_TEXTO,
          content: 'invalid evidence',
          createdById: fixture.owner.id,
        },
      });
    },
    (error) => {
      assert(/Foreign key constraint|P2003/i.test(error.message), 'Expected foreign key rejection for missing service_order_id on evidence');
    },
  );

  await expectReject(
    'Non-existing service_order_id rejected for report',
    async () => {
      await prisma.serviceReport.create({
        data: {
          serviceOrderId: randomUuid(),
          report: 'invalid report',
          createdById: fixture.owner.id,
        },
      });
    },
    (error) => {
      assert(/Foreign key constraint|P2003/i.test(error.message), 'Expected foreign key rejection for missing service_order_id on report');
    },
  );

  console.log('\nSUMMARY');
  for (const item of results) {
    console.log(`- ${item.status}: ${item.name}${item.details ? ` -> ${item.details}` : ''}`);
  }
  if (bugs.length) {
    console.log('\nBUGS FOUND');
    for (const item of bugs) {
      console.log(`- ${item}`);
    }
  }
  console.log('\nSERVICE ORDERS QA OK');
}

main()
  .catch((error) => {
    console.error('\nSERVICE ORDERS QA FAILED');
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await cleanup();
    await prisma.$disconnect();
  });