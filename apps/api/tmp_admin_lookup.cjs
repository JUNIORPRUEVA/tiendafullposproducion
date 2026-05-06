const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();
async function main() {
  const user = await prisma.user.findFirst({ where: { role: 'ADMIN' }, select: { id: true, email: true } });
  console.log(JSON.stringify(user || {}));
}
main().catch((e) => { console.error(String(e)); process.exit(1); }).finally(async () => { await prisma.$disconnect(); });
