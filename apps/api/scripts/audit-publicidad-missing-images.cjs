const baseUrl = 'http://localhost:4000';

async function request(method, path, token, body) {
  const headers = { 'content-type': 'application/json' };
  if (token) headers.authorization = `Bearer ${token}`;
  const res = await fetch(`${baseUrl}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json;
  try { json = JSON.parse(text); } catch { json = text; }
  return { status: res.status, body: json };
}

async function main() {
  const login = await request('POST', '/auth/login', null, {
    email: 'yr5985@gmail.com',
    password: 'Ayleen10.',
  });
  const token = login.body?.accessToken;
  if (!token) {
    console.log('LOGIN_FAIL', JSON.stringify(login.body));
    process.exit(1);
  }

  const assets = await request('GET', '/marketing/media-assets?active_only=true', token);
  const activeIds = (assets.body?.items ?? []).map((x) => x.id).filter(Boolean);

  for (const id of activeIds) {
    await request('PATCH', `/marketing/media-assets/${id}`, token, { is_active: false });
  }

  const date = new Date().toISOString().slice(0, 10);
  const generate = await request('POST', '/marketing/stories/generate-missing', token, { date });
  console.log('STATUS', generate.status);
  console.log(JSON.stringify(generate.body, null, 2));

  for (const id of activeIds) {
    await request('PATCH', `/marketing/media-assets/${id}`, token, { is_active: true });
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
