#!/usr/bin/env node

const { PrismaClient } = require('@prisma/client');

async function main() {
  const prisma = new PrismaClient();
  try {
    const row = await prisma.service.findFirst({
      select: {
        id: true,
        orderType: true,
        orderState: true,
        technicianId: true,
        orderExtras: true,
      },
    });

    console.log('Sample Service row (may be null if table empty):');
    console.dir(row, { depth: null });

    const count = await prisma.service.count();
    console.log('Service count:', count);
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
