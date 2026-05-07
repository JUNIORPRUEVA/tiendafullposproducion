const { PrismaClient } = require('@prisma/client');
const p = new PrismaClient();

async function main() {
  const cats = await p.product.groupBy({
    by: ['categoria'],
    _count: { id: true },
    orderBy: { _count: { id: 'desc' } },
    take: 20,
  });
  console.log('Categorias:');
  cats.forEach(c => console.log(` "${c.categoria}": ${c._count.id} productos`));

  const withImg = await p.product.count({
    where: { categoria: { contains: 'vigilancia', mode: 'insensitive' }, imagen: { not: null } },
  });
  console.log('\nProductos con "vigilancia" en categoria Y con imagen:', withImg);
}

main().finally(() => p.$disconnect());
