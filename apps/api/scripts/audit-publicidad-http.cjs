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
  let json = null;
  try {
    json = JSON.parse(text);
  } catch {
    json = text;
  }
  return { status: res.status, body: json };
}

async function main() {
  const login = await request('POST', '/auth/login', null, {
    email: 'yr5985@gmail.com',
    password: 'Ayleen10.',
  });

  if (login.status !== 201 && login.status !== 200) {
    console.log('LOGIN_FAIL', JSON.stringify(login, null, 2));
    process.exit(1);
  }

  const token = login.body.accessToken;
  const date = new Date().toISOString().slice(0, 10);

  const actions = [];
  actions.push({ name: 'generate-missing', ...(await request('POST', '/marketing/stories/generate-missing', token, { date })) });
  actions.push({ name: 'repair-incomplete', ...(await request('POST', '/marketing/stories/repair-incomplete', token, { date })) });
  actions.push({
    name: 'reset-clean',
    ...(await request('POST', '/marketing/reset-clean', token, {
      includeResearch: false,
      includeDraftMedia: true,
      includeGeneratedImages: true,
      includeApprovedStories: true,
      date,
    })),
  });

  const stories = await request('GET', `/marketing/stories?date=${date}`, token);
  actions.push({ name: 'stories-list', ...stories });

  const storyId = stories.body?.items?.[0]?.id;
  if (storyId) {
    actions.push({
      name: 'regenerate-image',
      ...(await request('POST', `/marketing/stories/${storyId}/regenerate-image`, token, { reason: 'audit' })),
    });

    const assets = await request('GET', '/marketing/media-assets?active_only=true', token);
    actions.push({ name: 'media-assets', ...assets });
    const mediaAssetId = assets.body?.items?.[0]?.id ?? '00000000-0000-0000-0000-000000000000';

    actions.push({
      name: 'change-base-image',
      ...(await request('PATCH', `/marketing/stories/${storyId}/base-image/${mediaAssetId}`, token)),
    });
  }

  for (const item of actions) {
    console.log(`ACTION ${item.name} STATUS ${item.status}`);
    console.log(JSON.stringify(item.body, null, 2));
    console.log('-----');
  }
}

main().catch((error) => {
  console.error('SCRIPT_ERROR', error?.stack || error);
  process.exit(1);
});
