// Manual Interno duplicate audit.
// Run: node audit-manual-interno.cjs

const crypto = require('crypto');
const { PrismaClient } = require('@prisma/client');

const prisma = new PrismaClient();

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

async function auditManualInterno() {
  console.log('Starting Manual Interno audit...\n');
  let hasFailure = false;

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
        starterKey: true,
        createdAt: true,
        updatedAt: true,
      },
      orderBy: [{ ownerId: 'asc' }, { updatedAt: 'desc' }],
    });

    console.log(`Total entries: ${entries.length}`);

    const groups = new Map();
    for (const entry of entries) {
      const key = dedupeKey(entry);
      const list = groups.get(key) || [];
      list.push(entry);
      groups.set(key, list);
    }

    const duplicateGroups = [...groups.values()].filter((g) => g.length > 1);
    console.log(`Exact duplicate groups: ${duplicateGroups.length}`);

    if (duplicateGroups.length > 0) {
      hasFailure = true;
      for (const group of duplicateGroups.slice(0, 20)) {
        const sample = group[0];
        console.log(
          `DUPLICATE owner=${sample.ownerId} title="${sample.title}" count=${group.length}`,
        );
        console.log(`  ids: ${group.map((g) => g.id).join(', ')}`);
      }
      if (duplicateGroups.length > 20) {
        console.log(`... ${duplicateGroups.length - 20} duplicate groups omitted`);
      }
    }

    const starterByOwner = new Map();
    for (const entry of entries) {
      if (!entry.starterKey || entry.starterKey.trim().length === 0) continue;
      const key = `${entry.ownerId}||${entry.starterKey}`;
      const list = starterByOwner.get(key) || [];
      list.push(entry.id);
      starterByOwner.set(key, list);
    }

    const starterDuplicates = [...starterByOwner.entries()].filter(([, ids]) => ids.length > 1);
    console.log(`Starter key duplicate groups: ${starterDuplicates.length}`);
    if (starterDuplicates.length > 0) {
      hasFailure = true;
      for (const [key, ids] of starterDuplicates.slice(0, 20)) {
        console.log(`STARTER_DUPLICATE ${key} ids=${ids.join(', ')}`);
      }
    }

    if (hasFailure) {
      console.error('\nAudit FAILED: duplicates detected.');
      process.exitCode = 1;
      return;
    }

    console.log('\nAudit OK: no duplicate groups detected.');
  } catch (error) {
    console.error('Audit error:', error);
    process.exitCode = 1;
  } finally {
    await prisma.$disconnect();
  }
}

auditManualInterno();
