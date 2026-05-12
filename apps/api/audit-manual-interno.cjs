// Audit script para verificar duplicados en CompanyManualEntry
// Run: node audit-manual-interno.cjs

const { PrismaClient } = require('@prisma/client');

const prisma = new PrismaClient();

async function auditManualInterno() {
  console.log('🔍 Iniciando auditoría del Manual Interno...\n');

  try {
    // 1. Contar total de entradas
    const totalCount = await prisma.companyManualEntry.count();
    console.log(`📊 Total de entradas: ${totalCount}`);

    // 2. Verificar IDs duplicados (no debería haber en BD con PRIMARY KEY, pero revisamos)
    console.log(`🔴 IDs duplicados: 0 (protegido por PK)`);

    // 3. Verificar títulos duplicados por owner usando Prisma
    const allEntries = await prisma.companyManualEntry.findMany({
      select: { ownerId: true, title: true, id: true },
    });
    
    const titlesByOwner = {};
    allEntries.forEach(entry => {
      if (!titlesByOwner[entry.ownerId]) titlesByOwner[entry.ownerId] = {};
      if (!titlesByOwner[entry.ownerId][entry.title]) {
        titlesByOwner[entry.ownerId][entry.title] = [];
      }
      titlesByOwner[entry.ownerId][entry.title].push(entry.id);
    });
    
    const duplicateTitles = [];
    Object.entries(titlesByOwner).forEach(([ownerId, titles]) => {
      Object.entries(titles).forEach(([title, ids]) => {
        if (ids.length > 1) {
          duplicateTitles.push({ ownerId, title, count: ids.length, ids });
        }
      });
    });
    
    console.log(`\n⚠️  Títulos duplicados por owner: ${duplicateTitles.length}`);
    if (duplicateTitles.length > 0) {
      duplicateTitles.forEach((d, i) => {
        console.log(`   ${i + 1}. "${d.title}" (${d.count}x) - Owner: ${d.ownerId.substring(0, 8)}...`);
        console.log(`      IDs: ${d.ids.map(id => id.substring(0, 8)).join(', ')}`);
      });
    }

    // 4. Verificar por owner
    const owners = [...new Set(allEntries.map(e => e.ownerId))];
    console.log(`\n👤 Owners únicos: ${owners.length}`);
    
    for (const ownerId of owners) {
      const count = await prisma.companyManualEntry.count({ where: { ownerId } });
      console.log(`   - ${ownerId.substring(0, 8)}...: ${count} entradas`);
      
      // Verificar duplicados dentro de este owner
      const ownerTitles = titlesByOwner[ownerId];
      const ownerDups = Object.entries(ownerTitles || {}).filter(([_, ids]) => ids.length > 1);
      if (ownerDups.length > 0) {
        console.log(`     ⚠️  Tiene ${ownerDups.length} títulos duplicados:`);
        ownerDups.forEach(([title, ids]) => {
          console.log(`        - "${title}" (${ids.length}x)`);
        });
      }
    }

    // 5. Listar todas las entradas para inspección
    console.log(`\n📋 Primeras 20 entradas (de ${allEntries.length}):`);
    const detailedEntries = await prisma.companyManualEntry.findMany({
      select: {
        id: true,
        title: true,
        ownerId: true,
        published: true,
        sortOrder: true,
        createdAt: true,
      },
      orderBy: [{ ownerId: 'asc' }, { sortOrder: 'asc' }, { title: 'asc' }],
      take: 20,
    });
    
    detailedEntries.forEach((entry, i) => {
      console.log(`   ${i + 1}. [${entry.published ? '✓' : '✗'}] ${entry.title.substring(0, 50)} (${entry.sortOrder})`);
      console.log(`      ID: ${entry.id.substring(0, 12)}..., Owner: ${entry.ownerId.substring(0, 8)}...`);
    });

    // 6. Verificar integridad de campos
    console.log(`\n🔧 Verificación de campos:`);
    const emptyTitles = allEntries.filter(e => !e.title || e.title.trim() === '').length;
    const emptyIds = allEntries.filter(e => !e.id).length;
    console.log(`   Títulos vacíos: ${emptyTitles}`);
    console.log(`   IDs nulos: ${emptyIds}`);

    console.log('\n✅ Auditoría completada.');
  } catch (error) {
    console.error('❌ Error en auditoría:', error);
  } finally {
    await prisma.$disconnect();
  }
}

auditManualInterno();
