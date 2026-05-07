require('dotenv').config();
const { PrismaClient } = require('@prisma/client');
const p = new PrismaClient();
p.marketingDailyStory.findMany({
  select: { id: true, type: true, status: true, imageStatus: true, generatedImageUrl: true, updatedAt: true },
  orderBy: { updatedAt: 'desc' },
  take: 10
}).then(r => {
  console.log(JSON.stringify(r, null, 2));
  return p.$disconnect();
});
