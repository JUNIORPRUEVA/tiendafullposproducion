const { PrismaClient } = require('@prisma/client');
const p = new PrismaClient();

async function main() {
  const all = await p.product.findMany({
    where: { categoria: { contains: 'sistema de vigilancia', mode: 'insensitive' } },
    select: { id: true, nombre: true, categoria: true, imagen: true },
    take: 5,
  });
  console.log('Encontrados (muestra 5):', all.length);
  all.forEach(x => console.log(' -', x.nombre, '| cat:', x.categoria, '| imagen:', x.imagen ? x.imagen.substring(0, 80) : 'NULL'));

  const withImg = await p.product.count({
    where: {
      categoria: { contains: 'sistema de vigilancia', mode: 'insensitive' },
      imagen: { not: null },
    },
  });
  console.log('Con imagen:', withImg);

  const total = await p.product.count({
    where: { categoria: { contains: 'sistema de vigilancia', mode: 'insensitive' } },
  });
  console.log('Total en categoria:', total);
}

main().finally(() => p.$disconnect());
