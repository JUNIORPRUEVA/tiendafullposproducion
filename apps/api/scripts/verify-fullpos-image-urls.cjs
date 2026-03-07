const { Client } = require('pg');

const connectionString = process.env.FULLPOS_REMOTE_URL;
const companyId = process.env.FULLPOS_COMPANY_ID || '2';

if (!connectionString) {
  console.error('FULLPOS_REMOTE_URL is required');
  process.exit(1);
}

async function checkUrl(url) {
  try {
    let response = await fetch(url, { method: 'HEAD' });
    if (response.status === 405 || response.status === 501) {
      response = await fetch(url, { method: 'GET' });
    }
    return {
      url,
      status: response.status,
      contentType: response.headers.get('content-type') || '',
      ok: response.ok,
    };
  } catch (error) {
    return {
      url,
      status: 0,
      contentType: error.message,
      ok: false,
    };
  }
}

async function main() {
  const client = new Client({ connectionString });
  await client.connect();

  const result = await client.query(
    `
      select id, name, "imageUrl"
      from public."Product"
      where "companyId"::text = $1
        and "imageUrl" is not null
        and btrim("imageUrl") <> ''
      order by id desc
    `,
    [companyId],
  );

  const rows = result.rows;
  const checks = [];
  for (const row of rows) {
    checks.push({
      id: row.id,
      name: row.name,
      ...(await checkUrl(row.imageUrl)),
    });
  }

  const summary = {
    total: checks.length,
    ok: checks.filter((item) => item.ok && item.contentType.toLowerCase().startsWith('image/')).length,
    broken: checks.filter((item) => !item.ok || !item.contentType.toLowerCase().startsWith('image/')).length,
  };

  const brokenSamples = checks.filter((item) => !item.ok || !item.contentType.toLowerCase().startsWith('image/')).slice(0, 20);

  console.log(JSON.stringify({ summary, brokenSamples }, null, 2));
  await client.end();
}

main().catch(async (error) => {
  console.error(JSON.stringify({ message: error.message, code: error.code ?? null, detail: error.detail ?? null }, null, 2));
  process.exitCode = 1;
});
