// Update script para publicar entradas del Manual Interno
// Run: node update-manual-interno-published.cjs

const { PrismaClient } = require('@prisma/client');

const prisma = new PrismaClient();

async function updatePublished() {
  console.log('📝 Actualizando estado de publicación...\n');

  try {
    // 1. Listar todas las entradas sin publicación
    const unpublished = await prisma.companyManualEntry.findMany({
      where: { published: false },
      select: { id: true, title: true, published: true },
    });

    console.log(`📊 Encontradas ${unpublished.length} entradas NO publicadas:`);
    unpublished.forEach((e, i) => {
      console.log(`   ${i + 1}. "${e.title}"`);
    });

    if (unpublished.length === 0) {
      console.log('✅ No hay entradas sin publicar.');
      return;
    }

    // 2. Actualizar todas a published = true
    console.log(`\n📝 Publicando ${unpublished.length} entrada(s)...`);
    const result = await prisma.companyManualEntry.updateMany({
      where: { published: false },
      data: { published: true },
    });

    console.log(`✓ Actualizadas ${result.count} entradas`);

    // 3. Verificar
    console.log(`\n📊 Estado final:`);
    const total = await prisma.companyManualEntry.count();
    const published = await prisma.companyManualEntry.count({ where: { published: true } });
    const notPublished = await prisma.companyManualEntry.count({ where: { published: false } });

    console.log(`   - Total: ${total}`);
    console.log(`   - Publicadas: ${published} ✓`);
    console.log(`   - Sin publicar: ${notPublished}`);

    if (notPublished === 0) {
      console.log('\n✅ Todas las entradas están publicadas correctamente.');
    }
  } catch (error) {
    console.error('❌ Error:', error);
    throw error;
  } finally {
    await prisma.$disconnect();
  }
}

updatePublished();
