import { Prisma, PrismaClient, Role } from '@prisma/client';
import * as bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

function isMissingUserTable(error: unknown) {
  if (typeof error === 'object' && error !== null) {
    const value = error as { code?: unknown; message?: unknown };
    const code = typeof value.code === 'string' ? value.code : '';
    const message = typeof value.message === 'string' ? value.message : '';
    return code === 'P2021' || message.includes('table `public.User` does not exist');
  }
  return false;
}

async function upsertUser({ email, password, nombreCompleto, telefono, role }: { email: string; password: string; nombreCompleto: string; telefono: string; role: Role }): Promise<{ id: string; email: string; fallback: boolean }> {
  const passwordHash = await bcrypt.hash(password, 10);
  try {
    const user = await prisma.user.upsert({
      where: { email },
      update: { nombreCompleto, telefono, role, passwordHash, blocked: false },
      create: { email, passwordHash, nombreCompleto, telefono, edad: 0, role, blocked: false, tieneHijos: false, estaCasado: false, casaPropia: false, vehiculo: false, licenciaConducir: false }
    });
    return { id: user.id, email: user.email, fallback: false };
  } catch (error) {
    if (!isMissingUserTable(error)) throw error;

    const rows = await prisma.$queryRaw<Array<{ id: string; email: string }>>(Prisma.sql`
      INSERT INTO users (email, "passwordHash", role)
      VALUES (${email}, ${passwordHash}, ${role})
      ON CONFLICT (email)
      DO UPDATE SET "passwordHash" = EXCLUDED."passwordHash", role = EXCLUDED.role
      RETURNING id, email
    `);

    const row = rows[0];
    if (!row) throw new Error('No se pudo upsert el usuario admin en tabla users');
    return { id: row.id, email: row.email, fallback: true };
  }
}

async function main() {
  const adminEmail = process.env.ADMIN_EMAIL || 'admin@fulltech.local';
  const adminPassword = process.env.ADMIN_PASSWORD;
  if (!adminPassword) throw new Error('ADMIN_PASSWORD is required to run seed');

  const sellerPassword = process.env.SELLER_PASSWORD || adminPassword;
  const seller1Email = process.env.SELLER1_EMAIL || 'vendedor1@fulltech.local';
  const seller2Email = process.env.SELLER2_EMAIL || 'vendedor2@fulltech.local';

  const admin = await upsertUser({
    email: adminEmail,
    password: adminPassword,
    nombreCompleto: 'Administrador',
    telefono: '0000000000',
    role: Role.ADMIN
  });

  if (admin.fallback) {
    console.log('Seed completed in fallback mode (users table):', {
      admin: admin.email,
      note: 'Solo se aseguró/reset el admin por compatibilidad de esquema.'
    });
    return;
  }

  const seller1 = await upsertUser({
    email: seller1Email,
    password: sellerPassword,
    nombreCompleto: 'Vendedor Uno',
    telefono: '8090000001',
    role: Role.VENDEDOR
  });

  const seller2 = await upsertUser({
    email: seller2Email,
    password: sellerPassword,
    nombreCompleto: 'Vendedor Dos',
    telefono: '8090000002',
    role: Role.VENDEDOR
  });

  const ensureProduct = async (nombre: string, precio: number, costo: number) => {
    const existing = await prisma.product.findFirst({ where: { nombre } });
    if (existing) {
      return prisma.product.update({ where: { id: existing.id }, data: { precio: new Prisma.Decimal(precio), costo: new Prisma.Decimal(costo) } });
    }
    return prisma.product.create({ data: { nombre, precio: new Prisma.Decimal(precio), costo: new Prisma.Decimal(costo) } });
  };

  const products = await Promise.all([
    ensureProduct('Laptop Pro 14"', 1450, 1100),
    ensureProduct('Monitor 27" 4K', 520, 360),
    ensureProduct('Mouse Inalámbrico', 35, 18)
  ]);

  const ensureClient = async (
    ownerId: string,
    nombre: string,
    data: { telefono?: string; email?: string; direccion?: string; notas?: string }
  ) => {
    const existing = await prisma.client.findFirst({ where: { ownerId, nombre } });
    if (existing) {
      return prisma.client.update({ where: { id: existing.id }, data });
    }
    return prisma.client.create({ data: { ownerId, nombre, ...data } });
  };

  const clients = await Promise.all([
    ensureClient(admin.id, 'Cliente Corporativo', {
      telefono: '8095550001',
      email: 'compras@corp.do',
      direccion: 'Av. Principal 123',
      notas: 'Prefiere facturas electrónicas'
    }),
    ensureClient(admin.id, 'Juan Pérez', {
      telefono: '8095550002',
      email: 'juanperez@mail.com'
    })
  ]);

  console.log('Seed completed:', {
    admin: admin.email,
    sellers: [seller1.email, seller2.email],
    products: products.map((p) => p.nombre),
    clients: clients.map((c) => c.nombre)
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
