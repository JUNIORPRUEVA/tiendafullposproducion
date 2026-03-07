const { Client } = require('pg');

const connectionString = process.env.FULLPOS_REMOTE_URL;
const companyId = process.env.FULLPOS_COMPANY_ID || '2';

if (!connectionString) {
  console.error('FULLPOS_REMOTE_URL is required');
  process.exit(1);
}

async function main() {
  const client = new Client({ connectionString });
  await client.connect();

  const stats = await client.query(
    `
      select
        count(*)::int as total,
        count(*) filter (where "imageUrl" is not null and btrim("imageUrl") <> '')::int as with_image,
        count(*) filter (where "imageUrl" is null or btrim("imageUrl") = '')::int as without_image
      from public."Product"
      where "companyId"::text = $1
    `,
    [companyId],
  );

  const samples = await client.query(
    `
      select id, name, "imageUrl"
      from public."Product"
      where "companyId"::text = $1
        and "imageUrl" is not null
        and btrim("imageUrl") <> ''
      order by id desc
      limit 20
    `,
    [companyId],
  );

  console.log(JSON.stringify({ stats: stats.rows[0], samples: samples.rows }, null, 2));
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
