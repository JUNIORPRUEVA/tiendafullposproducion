const { PrismaClient, Prisma } = require('@prisma/client');
const bcrypt = require('bcryptjs');

const prisma = new PrismaClient();

function isMissingUserTable(error) {
  if (error && typeof error === 'object') {
    const code = typeof error.code === 'string' ? error.code : '';
    const message = typeof error.message === 'string' ? error.message : '';
    return code === 'P2021' || message.includes('does not exist in the current database');
  }
  return false;
}

async function main() {
  const email = process.env.RESET_EMAIL || process.env.ADMIN_EMAIL || 'admin@fulltech.local';
  const password = process.env.RESET_PASSWORD || process.env.ADMIN_PASSWORD;

  if (!password) {
    throw new Error('RESET_PASSWORD (or ADMIN_PASSWORD) is required');
  }

  const passwordHash = await bcrypt.hash(password, 10);

  try {
    const updated = await prisma.user.update({
      where: { email },
      data: { passwordHash, blocked: false },
      select: { id: true, email: true },
    });

    console.log('Password reset OK (prisma.user):', updated.email);
    return;
  } catch (error) {
    if (!isMissingUserTable(error)) throw error;
  }

  const rows = await prisma.$queryRaw(
    Prisma.sql`
      UPDATE users
      SET "passwordHash" = ${passwordHash}
      WHERE email = ${email}
      RETURNING id, email
    `
  );

  if (!rows || rows.length === 0) {
    throw new Error(`User not found for email: ${email}`);
  }

  console.log('Password reset OK (users fallback):', rows[0].email);
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
