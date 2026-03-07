const { Client } = require('pg');

const connectionString = process.env.FULLPOS_DIRECT_DATABASE_URL;

if (!connectionString) {
  console.error('FULLPOS_DIRECT_DATABASE_URL is required');
  process.exit(1);
}

const mode = process.argv[2] || 'tables';

const queries = {
  tables: `
    select table_schema, table_name
    from information_schema.tables
    where table_schema not in ('information_schema', 'pg_catalog')
    order by table_schema, table_name
    limit 200
  `,
  columns: `
    select table_name, column_name, data_type
    from information_schema.columns
    where table_schema = 'public'
      and (
        table_name ilike '%product%'
        or table_name ilike '%company%'
        or table_name ilike '%tenant%'
        or table_name ilike '%business%'
        or table_name ilike '%category%'
        or table_name ilike '%categoria%'
      )
    order by table_name, ordinal_position
  `,
  'product-fks': `
    select
      tc.table_name,
      kcu.column_name,
      ccu.table_name as foreign_table_name,
      ccu.column_name as foreign_column_name
    from information_schema.table_constraints tc
    join information_schema.key_column_usage kcu
      on tc.constraint_name = kcu.constraint_name
     and tc.table_schema = kcu.table_schema
    join information_schema.constraint_column_usage ccu
      on ccu.constraint_name = tc.constraint_name
     and ccu.table_schema = tc.table_schema
    where tc.constraint_type = 'FOREIGN KEY'
      and tc.table_schema = 'public'
      and tc.table_name ilike '%product%'
    order by tc.table_name, kcu.column_name
  `,
  sample: `
    select *
    from public.products
    limit 5
  `,
};

const query = queries[mode];

if (!query) {
  console.error(`Unknown mode: ${mode}`);
  process.exit(1);
}

const client = new Client({ connectionString });

(async () => {
  await client.connect();
  const result = await client.query(query);
  console.log(JSON.stringify(result.rows, null, 2));
  await client.end();
})().catch(async (error) => {
  console.error(error);
  try {
    await client.end();
  } catch {}
  process.exit(1);
});