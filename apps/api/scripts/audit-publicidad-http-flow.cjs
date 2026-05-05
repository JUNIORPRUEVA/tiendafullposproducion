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
  try {
    json = JSON.parse(text);
  } catch {
    json = text;
  }
  return { status: res.status, body: json };
}

function printResult(name, result) {
  console.log(`ACTION ${name} STATUS ${result.status}`);
  console.log(JSON.stringify(result.body, null, 2));
  console.log('-----');
}

async function main() {
  const login = await request('POST', '/auth/login', null, {
    email: 'yr5985@gmail.com',
    password: 'Ayleen10.',
  });
  if (![200, 201].includes(login.status)) {
    printResult('login', login);
    process.exit(1);
  }

  const token = login.body.accessToken;
  const date = new Date().toISOString().slice(0, 10);

  const createAsset = await request('POST', '/marketing/media-assets', token, {
    file_url: 'https://images.unsplash.com/photo-1558002038-1055907df827?auto=format&fit=crop&w=1080&q=80',
    file_name: `audit-publicidad-${Date.now()}.jpg`,
    mime_type: 'image/jpeg',
    category: 'Instalaciones reales',
    related_service: 'Cámaras de seguridad',
    tags: ['publicidad', 'auditoria'],
    description: 'Asset de auditoria para probar flujo de generacion',
    is_active: true,
    is_featured: true,
  });
  printResult('create-media-asset', createAsset);

  const generate = await request('POST', '/marketing/stories/generate-missing', token, { date });
  printResult('generate-missing', generate);

  const stories = await request('GET', `/marketing/stories?date=${date}`, token);
  printResult('stories-list', stories);

  const firstStoryId = stories.body?.items?.[0]?.id;
  if (!firstStoryId) {
    console.log('NO_STORY_CREATED');
    process.exit(0);
  }

  const regenerateImage = await request(
    'POST',
    `/marketing/stories/${firstStoryId}/regenerate-image`,
    token,
    { reason: 'auditoria regeneracion' },
  );
  printResult('regenerate-image', regenerateImage);

  const activeAssets = await request('GET', '/marketing/media-assets?active_only=true', token);
  printResult('media-assets', activeAssets);

  const mediaAssetId = activeAssets.body?.items?.[0]?.id;
  if (!mediaAssetId) {
    console.log('NO_ACTIVE_ASSET');
    process.exit(0);
  }

  const changeBaseImage = await request(
    'PATCH',
    `/marketing/stories/${firstStoryId}/base-image/${mediaAssetId}`,
    token,
    null,
  );
  printResult('change-base-image', changeBaseImage);

  const repair = await request('POST', '/marketing/stories/repair-incomplete', token, { date });
  printResult('repair-incomplete', repair);

  const reset = await request('POST', '/marketing/reset-clean', token, {
    includeResearch: false,
    includeDraftMedia: true,
    includeGeneratedImages: true,
    includeApprovedStories: true,
    date,
  });
  printResult('reset-clean', reset);
}

main().catch((error) => {
  console.error('SCRIPT_ERROR', error?.stack || error);
  process.exit(1);
});
