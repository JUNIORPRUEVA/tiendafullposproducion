/* eslint-disable no-console */

import { PrismaClient } from '@prisma/client';

type Args = {
  ownerId?: string;
  allOwners: boolean;
  includeServices: boolean;
  execute: boolean;
  confirm?: string;
  help: boolean;
};

type PurgeSummary = {
  clients: number;
  quotations: number;
  serviceOrders: number;
  serviceOrderEvidences: number;
  serviceOrderReports: number;
  serviceOrderNotificationJobs: number;
  payrollServiceCommissionRequests: number;
  legacyServices: number;
  salesLinkedToClients: number;
};

const REQUIRED_CONFIRMATION = 'PURGE_CLIENTS_AND_SERVICE_ORDERS';

function parseArgs(argv: string[]): Args {
  const args: Args = {
    allOwners: false,
    includeServices: false,
    execute: false,
    help: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const current = argv[index];
    const next = argv[index + 1];

    if (current === '--help' || current === '-h') {
      args.help = true;
      continue;
    }

    if (current === '--all-owners') {
      args.allOwners = true;
      continue;
    }

    if (current === '--include-services') {
      args.includeServices = true;
      continue;
    }

    if (current === '--execute') {
      args.execute = true;
      continue;
    }

    if (current.startsWith('--owner-id=')) {
      args.ownerId = current.slice('--owner-id='.length).trim();
      continue;
    }

    if (current === '--owner-id' && next) {
      args.ownerId = next.trim();
      index += 1;
      continue;
    }

    if (current.startsWith('--confirm=')) {
      args.confirm = current.slice('--confirm='.length).trim();
      continue;
    }

    if (current === '--confirm' && next) {
      args.confirm = next.trim();
      index += 1;
      continue;
    }

    throw new Error(`Argumento no reconocido: ${current}`);
  }

  return args;
}

function printUsage() {
  console.log(`
Uso:
  npx ts-node scripts/purge-clients-service-orders.ts --owner-id <uuid>
  npx ts-node scripts/purge-clients-service-orders.ts --owner-id <uuid> --include-services --execute --confirm ${REQUIRED_CONFIRMATION}
  npx ts-node scripts/purge-clients-service-orders.ts --all-owners --execute --confirm ${REQUIRED_CONFIRMATION}

Comportamiento:
  - Por defecto corre en DRY-RUN y solo muestra conteos.
  - Borra clientes, cotizaciones y ordenes de servicio relacionadas.
  - Si agregas --include-services, tambien borra registros del modulo legacy Service ligados a esos clientes.
  - Si existen registros en Service y no usas --include-services, el script se detiene en modo execute para no dejar clientes bloqueados por FK.

Flags:
  --owner-id <uuid>        Limita el borrado a un owner concreto.
  --all-owners             Aplica a todos los owners.
  --include-services       Incluye la tabla Service y sus cascadas.
  --execute                Ejecuta el borrado real.
  --confirm <texto>        Debe ser exactamente ${REQUIRED_CONFIRMATION}.
  --help                   Muestra esta ayuda.
`);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (args.help) {
    printUsage();
    return;
  }

  if (!args.ownerId && !args.allOwners) {
    throw new Error('Debes indicar --owner-id <uuid> o usar --all-owners.');
  }

  if (args.ownerId && args.allOwners) {
    throw new Error('Usa solo una opcion de alcance: --owner-id o --all-owners.');
  }

  if (args.execute && args.confirm !== REQUIRED_CONFIRMATION) {
    throw new Error(`Confirmacion invalida. Usa --confirm ${REQUIRED_CONFIRMATION}`);
  }

  const prisma = new PrismaClient();

  try {
    const clientWhere = args.allOwners ? {} : { ownerId: args.ownerId };

    const clients = await prisma.client.findMany({
      where: clientWhere,
      select: { id: true, ownerId: true },
      orderBy: { createdAt: 'asc' },
    });

    const clientIds = clients.map((item) => item.id);
    const ownerIds = Array.from(new Set(clients.map((item) => item.ownerId)));

    if (clientIds.length === 0) {
      console.log('No se encontraron clientes para el alcance indicado.');
      return;
    }

    const [
      quotations,
      serviceOrders,
      legacyServices,
      salesLinkedToClients,
    ] = await Promise.all([
      prisma.cotizacion.findMany({
        where: { customerId: { in: clientIds } },
        select: { id: true },
      }),
      prisma.serviceOrder.findMany({
        where: { clientId: { in: clientIds } },
        select: { id: true },
      }),
      prisma.service.findMany({
        where: { customerId: { in: clientIds } },
        select: { id: true },
      }),
      prisma.sale.count({
        where: { customerId: { in: clientIds } },
      }),
    ]);

    const quotationIds = quotations.map((item) => item.id);
    const serviceOrderIds = serviceOrders.map((item) => item.id);
    const legacyServiceIds = legacyServices.map((item) => item.id);

    const [
      serviceOrderEvidences,
      serviceOrderReports,
      serviceOrderNotificationJobs,
      payrollServiceCommissionRequests,
    ] = await Promise.all([
      prisma.serviceEvidence.count({
        where: { serviceOrderId: { in: serviceOrderIds } },
      }),
      prisma.serviceReport.count({
        where: { serviceOrderId: { in: serviceOrderIds } },
      }),
      prisma.serviceOrderNotificationJob.count({
        where: { orderId: { in: serviceOrderIds } },
      }),
      prisma.payrollServiceCommissionRequest.count({
        where: { serviceOrderId: { in: serviceOrderIds } },
      }),
    ]);

    const summary: PurgeSummary = {
      clients: clientIds.length,
      quotations: quotationIds.length,
      serviceOrders: serviceOrderIds.length,
      serviceOrderEvidences,
      serviceOrderReports,
      serviceOrderNotificationJobs,
      payrollServiceCommissionRequests,
      legacyServices: legacyServiceIds.length,
      salesLinkedToClients,
    };

    console.log('Resumen del borrado solicitado:');
    console.log(JSON.stringify({
      mode: args.execute ? 'EXECUTE' : 'DRY_RUN',
      scope: args.allOwners ? 'ALL_OWNERS' : 'OWNER',
      ownerId: args.ownerId ?? null,
      ownerCount: ownerIds.length,
      includeServices: args.includeServices,
      summary,
    }, null, 2));

    if (summary.salesLinkedToClients > 0) {
      console.log(
        'Nota: hay ventas ligadas a estos clientes. Al borrar clientes, Sale.customerId quedara en NULL por FK onDelete SetNull.',
      );
    }

    if (summary.legacyServices > 0 && !args.includeServices) {
      const message =
        'Hay registros en Service para estos clientes. Para poder borrar los clientes sin bloqueo por FK, vuelve a correr con --include-services.';

      if (args.execute) {
        throw new Error(message);
      }

      console.log(`Advertencia: ${message}`);
    }

    if (!args.execute) {
      console.log('DRY-RUN completado. No se hicieron cambios.');
      return;
    }

    const deleted = await prisma.$transaction(async (tx) => {
      const serviceOrdersDeleted = serviceOrderIds.length
        ? await tx.serviceOrder.deleteMany({ where: { id: { in: serviceOrderIds } } })
        : { count: 0 };

      const quotationsDeleted = quotationIds.length
        ? await tx.cotizacion.deleteMany({ where: { id: { in: quotationIds } } })
        : { count: 0 };

      const legacyServicesDeleted = args.includeServices && legacyServiceIds.length
        ? await tx.service.deleteMany({ where: { id: { in: legacyServiceIds } } })
        : { count: 0 };

      const clientsDeleted = clientIds.length
        ? await tx.client.deleteMany({ where: { id: { in: clientIds } } })
        : { count: 0 };

      return {
        serviceOrdersDeleted: serviceOrdersDeleted.count,
        quotationsDeleted: quotationsDeleted.count,
        legacyServicesDeleted: legacyServicesDeleted.count,
        clientsDeleted: clientsDeleted.count,
      };
    });

    console.log('Borrado completado:');
    console.log(JSON.stringify(deleted, null, 2));
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});