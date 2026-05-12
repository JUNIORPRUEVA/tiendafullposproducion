// Duplicate cleanup for CompanyManualEntry.
// Run:
//   node fix-manual-interno-duplicates.cjs --dry-run
//   node fix-manual-interno-duplicates.cjs --apply

const crypto = require('crypto');
const { PrismaClient } = require('@prisma/client');

const prisma = new PrismaClient();
const isApply = process.argv.includes('--apply');
const isDryRun = !isApply;

function normalizeText(value) {
  return `${value ?? ''}`
    .trim()
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

function dedupeKey(entry) {
  const roles = [...new Set((entry.targetRoles || []).map((r) => `${r}`.trim().toUpperCase()))]
    .filter((r) => r.length > 0)
    .sort()
    .join('|');
  const contentHash = crypto
    .createHash('sha256')
    .update(normalizeText(entry.content))
    .digest('hex');

  return [
    entry.ownerId,
    normalizeText(entry.title),
    entry.kind,
    entry.audience,
    normalizeText(entry.moduleKey),
    roles,
    contentHash,
  ].join('||');
}

function sortKeepFirst(left, right) {
  const lu = new Date(left.updatedAt || left.createdAt || 0).getTime();
  const ru = new Date(right.updatedAt || right.createdAt || 0).getTime();
  if (ru !== lu) return ru - lu;
  const lc = new Date(left.createdAt || 0).getTime();
  const rc = new Date(right.createdAt || 0).getTime();
  if (rc !== lc) return rc - lc;
  return `${right.id}`.localeCompare(`${left.id}`);
}

async function fixDuplicates() {
  console.log(`Starting duplicate cleanup (${isDryRun ? 'DRY RUN' : 'APPLY'})...\n`);

  try {
    const entries = await prisma.companyManualEntry.findMany({
      select: {
        id: true,
        ownerId: true,
        title: true,
        content: true,
        kind: true,
        audience: true,
        moduleKey: true,
        targetRoles: true,
        createdAt: true,
        updatedAt: true,
      },
    });

    const groups = new Map();
    for (const entry of entries) {
      const key = dedupeKey(entry);
      const list = groups.get(key) || [];
      list.push(entry);
      groups.set(key, list);
    }

    const duplicateGroups = [...groups.values()].filter((group) => group.length > 1);
    if (duplicateGroups.length === 0) {
      console.log('No duplicate groups found.');
      return;
    }

    const keepIds = [];
    const deleteIds = [];

    for (const group of duplicateGroups) {
      const sorted = [...group].sort(sortKeepFirst);
      keepIds.push(sorted[0].id);
      for (const entry of sorted.slice(1)) {
        deleteIds.push(entry.id);
      }
    }

    console.log(`Duplicate groups: ${duplicateGroups.length}`);
    console.log(`Records to keep: ${keepIds.length}`);
    console.log(`Records to delete: ${deleteIds.length}`);

    for (const group of duplicateGroups.slice(0, 20)) {
      const sorted = [...group].sort(sortKeepFirst);
      console.log(`KEEP ${sorted[0].id} title="${sorted[0].title}" owner=${sorted[0].ownerId}`);
      for (const dup of sorted.slice(1)) {
        console.log(`  DELETE ${dup.id}`);
      }
    }
    if (duplicateGroups.length > 20) {
      console.log(`... ${duplicateGroups.length - 20} groups omitted`);
    }

    if (isDryRun) {
      console.log('\nDry run completed. Re-run with --apply to execute deletions.');
      return;
    }

    const batchSize = 200;
    let deletedCount = 0;
    for (let i = 0; i < deleteIds.length; i += batchSize) {
      const batch = deleteIds.slice(i, i + batchSize);
      const result = await prisma.companyManualEntry.deleteMany({
        where: { id: { in: batch } },
      });
      deletedCount += result.count;
      console.log(`Deleted ${deletedCount}/${deleteIds.length}`);
    }

    console.log('\nCleanup completed.');
    console.log(`Deleted rows: ${deletedCount}`);
  } catch (error) {
    console.error('Cleanup error:', error);
    process.exitCode = 1;
  } finally {
    await prisma.$disconnect();
  }
}

fixDuplicates();
