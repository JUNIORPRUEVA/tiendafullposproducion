// Fix script para eliminar duplicados en CompanyManualEntry
// Run: node fix-manual-interno-duplicates.cjs

const { PrismaClient } = require('@prisma/client');

const prisma = new PrismaClient();

async function fixDuplicates() {
  console.log('🔧 Iniciando limpieza de duplicados...\n');

  try {
    // 1. Obtener todas las entradas con el título duplicado
    const duplicateTitle = 'Horario, puntualidad, ponche y horas extras';
    const entries = await prisma.companyManualEntry.findMany({
      where: { title: duplicateTitle },
      orderBy: { createdAt: 'asc' },
      select: { id: true, createdAt: true, published: true, sortOrder: true },
    });

    console.log(`📊 Encontradas ${entries.length} entradas con título: "${duplicateTitle}"`);

    if (entries.length === 0) {
      console.log('✅ No hay duplicados para eliminar.');
      return;
    }

    // 2. Decidir cuál mantener: la más antigua (original)
    const toKeep = entries[0];
    const toDelete = entries.slice(1);

    console.log(`\n💾 Manteniendo entrada más antigua:`);
    console.log(`   ID: ${toKeep.id}`);
    console.log(`   Creada: ${toKeep.createdAt}`);

    console.log(`\n🗑️  Eliminando ${toDelete.length} entradas duplicadas...`);

    // 3. Eliminar en lotes para evitar timeouts
    const batchSize = 100;
    let deleted = 0;
    for (let i = 0; i < toDelete.length; i += batchSize) {
      const batch = toDelete.slice(i, i + batchSize);
      const result = await prisma.companyManualEntry.deleteMany({
        where: { id: { in: batch.map(e => e.id) } },
      });
      deleted += result.count;
      console.log(`   ✓ Eliminadas ${result.count} entradas (${deleted}/${toDelete.length})`);
    }

    console.log(`\n📊 Resumen final:`);
    const totalAfter = await prisma.companyManualEntry.count();
    console.log(`   - Entradas antes: ${entries.length}`);
    console.log(`   - Entradas eliminadas: ${deleted}`);
    console.log(`   - Total en BD: ${totalAfter}`);

    // 4. Verificar que no hay más duplicados del mismo título
    const check = await prisma.companyManualEntry.findMany({
      where: { title: duplicateTitle },
      select: { id: true },
    });
    console.log(`   - Verificación "${duplicateTitle}": ${check.length} entrada(s) ✓`);

    console.log('\n✅ Limpieza completada correctamente.');
  } catch (error) {
    console.error('❌ Error al eliminar duplicados:', error);
    throw error;
  } finally {
    await prisma.$disconnect();
  }
}

fixDuplicates();
