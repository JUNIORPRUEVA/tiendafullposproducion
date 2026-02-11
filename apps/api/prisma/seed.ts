import { PrismaClient, Role } from '@prisma/client';
import * as bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

async function main() {
  const email = 'admin@fulltech.local';
  const plainPassword = 'Admin12345!';

  const existing = await prisma.user.findUnique({ where: { email } });
  if (existing) return;

  const passwordHash = await bcrypt.hash(plainPassword, 10);
  await prisma.user.create({
    data: {
      email,
      passwordHash,
      nombreCompleto: 'Administrador',
      telefono: '0000000000',
      edad: 0,
      role: Role.ADMIN,
      blocked: false
    }
  });
}

main()
  .then(async () => {
    await prisma.$disconnect();
  })
  .catch(async (e) => {
    console.error(e);
    await prisma.$disconnect();
    process.exit(1);
  });
