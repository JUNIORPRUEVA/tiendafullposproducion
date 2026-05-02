#!/usr/bin/env node

const { Client } = require('pg');
const { execFileSync } = require('child_process');

const MIGRATION_NAME =
  process.argv[2] ||
  '20260502043000_add_status_history_user_name_and_created_at';
const DEPLOY_AFTER_RESOLVE = process.argv.includes('--deploy-after-resolve');

const TABLE_NAME = 'service_order_status_history';
const REQUIRED_COLUMNS = ['changed_by_user_name', 'created_at'];

const TABLE_EXISTS_SQL = `
SELECT EXISTS (
  SELECT 1
  FROM information_schema.tables
  WHERE table_schema = current_schema()
    AND table_name = $1
) AS table_exists;
`;

const COLUMNS_SQL = `
SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = current_schema()
  AND table_name = $1
  AND column_name = ANY($2::text[])
ORDER BY column_name;
`;

function log(message) {
  console.log(`[migration-resolver] ${message}`);
}

function runPrisma(args) {
  const command = process.platform === 'win32' ? 'npx.cmd' : 'npx';
  execFileSync(command, args, { stdio: 'inherit' });
}

async function inspectMigrationState() {
  const databaseUrl = process.env.DATABASE_URL;
  if (!databaseUrl) {
    throw new Error('DATABASE_URL no esta configurado');
  }

  const client = new Client({ connectionString: databaseUrl });
  await client.connect();

  try {
    const tableExistsResult = await client.query(TABLE_EXISTS_SQL, [TABLE_NAME]);
    const tableExists = tableExistsResult.rows[0]?.table_exists === true;

    const columnsResult = await client.query(COLUMNS_SQL, [
      TABLE_NAME,
      REQUIRED_COLUMNS,
    ]);

    return {
      tableExists,
      columns: columnsResult.rows,
    };
  } finally {
    await client.end();
  }
}

function decideResolution(state) {
  if (!state.tableExists) {
    return {
      action: 'rolled-back',
      reason: `table "${TABLE_NAME}" no existe en el esquema actual`,
    };
  }

  const columnMap = new Map(
    state.columns.map((column) => [column.column_name, column]),
  );

  const changedByUserName = columnMap.get('changed_by_user_name');
  const createdAt = columnMap.get('created_at');

  const hasChangedByUserName = Boolean(changedByUserName);
  const hasCreatedAt = Boolean(createdAt);
  const createdAtIsNotNull = createdAt?.is_nullable === 'NO';
  const createdAtHasDefault =
    typeof createdAt?.column_default === 'string' &&
    createdAt.column_default.trim().length > 0;

  if (
    hasChangedByUserName &&
    hasCreatedAt &&
    createdAtIsNotNull &&
    createdAtHasDefault
  ) {
    return {
      action: 'applied',
      reason:
        'las columnas requeridas ya existen y created_at conserva NOT NULL + DEFAULT',
    };
  }

  const missingBits = [];
  if (!hasChangedByUserName) missingBits.push('changed_by_user_name');
  if (!hasCreatedAt) {
    missingBits.push('created_at');
  } else {
    if (!createdAtIsNotNull) missingBits.push('created_at NOT NULL');
    if (!createdAtHasDefault) missingBits.push('created_at DEFAULT');
  }

  return {
    action: 'rolled-back',
    reason: `faltan cambios esperados: ${missingBits.join(', ')}`,
  };
}

async function main() {
  log(`inspecting failed migration "${MIGRATION_NAME}"`);
  log(`validation query (table): ${TABLE_EXISTS_SQL.trim()}`);
  log(`validation query (columns): ${COLUMNS_SQL.trim()}`);

  const state = await inspectMigrationState();
  log(`table "${TABLE_NAME}" exists=${state.tableExists}`);
  log(
    `columns found=${state.columns.length} details=${JSON.stringify(
      state.columns,
    )}`,
  );

  const decision = decideResolution(state);
  log(
    `decision=${decision.action} migration="${MIGRATION_NAME}" reason="${decision.reason}"`,
  );

  if (decision.action === 'applied') {
    runPrisma([
      'prisma',
      'migrate',
      'resolve',
      '--applied',
      MIGRATION_NAME,
    ]);
    log(`successfully marked migration "${MIGRATION_NAME}" as applied`);
  } else {
    runPrisma([
      'prisma',
      'migrate',
      'resolve',
      '--rolled-back',
      MIGRATION_NAME,
    ]);
    log(`successfully marked migration "${MIGRATION_NAME}" as rolled-back`);
  }

  if (DEPLOY_AFTER_RESOLVE) {
    log(
      `retrying prisma migrate deploy after ${decision.action} resolution`,
    );
    runPrisma(['prisma', 'migrate', 'deploy']);
    log(`prisma migrate deploy completed after ${decision.action} resolution`);
  }
}

main().catch((error) => {
  log(
    `failed to resolve migration "${MIGRATION_NAME}": ${
      error?.message || error
    }`,
  );
  process.exit(1);
});
