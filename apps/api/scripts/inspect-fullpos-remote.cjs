const { Client } = require('pg');

const connectionString = process.env.FULLPOS_REMOTE_URL;

if (!connectionString) {
  console.error('FULLPOS_REMOTE_URL is required');
  process.exit(1);
}

async function main() {
  const client = new Client({ connectionString });
  await client.connect();

  const tables = await client.query(`
    select table_name
    from information_schema.tables
    where table_schema = 'public'
    order by table_name
  `);

  const names = tables.rows.map((row) => row.table_name);
  const interesting = names.filter((name) => /product|categor|item|invent/i.test(name));

  const columns = await client.query(
    `
      select table_name, column_name, data_type
      from information_schema.columns
      where table_schema = 'public'
        and table_name = any($1)
      order by table_name, ordinal_position
    `,
    [interesting],
  );

  console.log(JSON.stringify({ interesting, columns: columns.rows }, null, 2));
  await client.end();
}

main().catch(async (error) => {
  console.error(
    JSON.stringify(
      {
        message: error.message,
        code: error.code ?? null,
        detail: error.detail ?? null,
      },
      null,
      2,
    ),
  );
  process.exitCode = 1;
});
