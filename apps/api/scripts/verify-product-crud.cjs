const { PrismaClient } = require('@prisma/client');

const prisma = new PrismaClient();

async function main() {
  const marker = `verif-${Date.now()}`;

  const created = await prisma.product.create({
    data: {
      nombre: `Producto ${marker}`,
      categoria: 'General',
      costo: 10.5,
      precio: 20.75,
      imagen: `/uploads/${marker}.jpg`,
    },
  });

  const updated = await prisma.product.update({
    where: { id: created.id },
    data: {
      nombre: `Producto ${marker} upd`,
      categoria: 'Electronica',
      costo: 11,
      precio: 21,
      imagen: `/uploads/${marker}-upd.jpg`,
    },
  });

  const fetched = await prisma.product.findUnique({ where: { id: created.id } });
  if (!fetched) throw new Error('No se pudo leer el producto creado');

  await prisma.product.delete({ where: { id: created.id } });

  console.log('PRODUCT_CRUD_OK');
  console.log(JSON.stringify({ createdId: created.id, updatedNombre: updated.nombre }, null, 2));
}

main()
  .catch((error) => {
    console.error('PRODUCT_CRUD_FAIL');
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
