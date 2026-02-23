import { Prisma, PrismaClient, Role, SaleStatus } from '@prisma/client';
import * as bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

async function upsertUser({ email, password, nombreCompleto, telefono, role }: { email: string; password: string; nombreCompleto: string; telefono: string; role: Role }) {
  const passwordHash = await bcrypt.hash(password, 10);
  return prisma.user.upsert({
    where: { email },
    update: { nombreCompleto, telefono, role, passwordHash, blocked: false },
    create: { email, passwordHash, nombreCompleto, telefono, edad: 0, role, blocked: false, tieneHijos: false, estaCasado: false, casaPropia: false, vehiculo: false, licenciaConducir: false }
  });
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

  const ensureClient = async (nombre: string, data: { telefono?: string; email?: string; direccion?: string; notas?: string }) => {
    const existing = await prisma.client.findFirst({ where: { nombre } });
    if (existing) {
      return prisma.client.update({ where: { id: existing.id }, data });
    }
    return prisma.client.create({ data: { nombre, ...data } });
  };

  const clients = await Promise.all([
    ensureClient('Cliente Corporativo', {
      telefono: '8095550001',
      email: 'compras@corp.do',
      direccion: 'Av. Principal 123',
      notas: 'Prefiere facturas electrónicas'
    }),
    ensureClient('Juan Pérez', {
      telefono: '8095550002',
      email: 'juanperez@mail.com'
    })
  ]);

  // Seed a confirmed sale for seller1 with 2 items
  const sale = await prisma.sale.create({
    data: {
      sellerId: seller1.id,
      clientId: clients[0].id,
      status: SaleStatus.CONFIRMED,
      note: 'Venta de ejemplo seed',
      subtotal: new Prisma.Decimal(0),
      totalCost: new Prisma.Decimal(0),
      profit: new Prisma.Decimal(0),
      commission: new Prisma.Decimal(0)
    }
  });

  const seedItems = [
    { product: products[0], qty: 1, unitPrice: products[0].precio },
    { product: products[1], qty: 2, unitPrice: products[1].precio }
  ];

  let subtotal = new Prisma.Decimal(0);
  let totalCost = new Prisma.Decimal(0);
  let profit = new Prisma.Decimal(0);

  for (const item of seedItems) {
    const qtyDec = new Prisma.Decimal(item.qty);
    const lineTotal = item.unitPrice.mul(qtyDec);
    const lineCost = item.product.costo.mul(qtyDec);
    const lineProfit = lineTotal.sub(lineCost);

    await prisma.saleItem.create({
      data: {
        saleId: sale.id,
        productId: item.product.id,
        qty: item.qty,
        unitPriceSold: item.unitPrice,
        unitCostSnapshot: item.product.costo,
        lineTotal,
        lineCost,
        lineProfit
      }
    });

    subtotal = subtotal.add(lineTotal);
    totalCost = totalCost.add(lineCost);
    profit = profit.add(lineProfit);
  }

  const commission = profit.greaterThan(0) ? profit.mul(0.1) : new Prisma.Decimal(0);
  await prisma.sale.update({ where: { id: sale.id }, data: { subtotal, totalCost, profit, commission } });

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
