import * as fs from 'node:fs';
import * as path from 'node:path';

import { PrismaClient } from '@prisma/client';
import { JwtService } from '@nestjs/jwt';
import { S3Client, HeadObjectCommand, HeadObjectCommandOutput } from '@aws-sdk/client-s3';

import { normalizeJwtSecret } from '../src/auth/jwt.util';

function loadDotEnv(envPath: string) {
  if (!fs.existsSync(envPath)) return;
  const raw = fs.readFileSync(envPath, 'utf8');
  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq <= 0) continue;
    const key = trimmed.slice(0, eq).trim();
    let value = trimmed.slice(eq + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    if (!(key in process.env)) {
      process.env[key] = value;
    }
  }
}

function inferMimeType(fileName: string) {
  const ext = path.extname(fileName).toLowerCase();
  if (ext === '.jpg' || ext === '.jpeg') return 'image/jpeg';
  if (ext === '.png') return 'image/png';
  if (ext === '.webp') return 'image/webp';
  if (ext === '.mp4') return 'video/mp4';
  return 'application/octet-stream';
}

function findSampleUploadFile(repoRoot: string) {
  const candidates = [
    path.join(repoRoot, 'apps', 'fulltech_app', 'assets', 'image'),
    path.join(repoRoot, 'apps', 'fulltech_app', 'assets'),
    path.join(repoRoot, 'assets', 'image'),
  ];

  const exts = new Set(['.jpg', '.jpeg', '.png', '.webp']);

  const walk = (dir: string): string | null => {
    if (!fs.existsSync(dir)) return null;
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    for (const entry of entries) {
      const abs = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        const found = walk(abs);
        if (found) return found;
        continue;
      }
      const ext = path.extname(entry.name).toLowerCase();
      if (exts.has(ext)) return abs;
    }
    return null;
  };

  for (const dir of candidates) {
    const found = walk(dir);
    if (found) return found;
  }

  return null;
}

async function httpJson<T>(url: string, init: RequestInit): Promise<T> {
  const res = await fetch(url, init);
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`HTTP ${res.status} ${res.statusText} for ${url}: ${text.slice(0, 500)}`);
  }
  return JSON.parse(text) as T;
}

async function main() {
  // Match Nest ConfigModule.forRoot envFilePath behavior.
  // When running from apps/api, process.cwd() is typically apps/api.
  const cwd = process.cwd();
  loadDotEnv(path.join(cwd, '.env'));
  loadDotEnv(path.join(cwd, '..', '.env'));
  loadDotEnv(path.join(cwd, '..', '..', '.env'));

  const apiBaseUrl = (process.env.API_BASE_URL ?? 'http://localhost:4000').trim().replace(/\/$/, '');

  const prisma = new PrismaClient();

  const user = await prisma.user.findFirst({
    where: { blocked: false },
    orderBy: { createdAt: 'asc' },
    select: { id: true, email: true, role: true },
  });

  if (!user) {
    throw new Error('No hay usuarios en la BD. Necesito al menos 1 usuario para firmar JWT.');
  }

  const service = await prisma.service.findFirst({
    where: { isDeleted: false },
    orderBy: { createdAt: 'desc' },
    select: { id: true },
  });

  if (!service) {
    throw new Error('No hay servicios en la BD. Necesito al menos 1 service para probar storage.');
  }

  const jwtSecret = normalizeJwtSecret(process.env.JWT_SECRET) ?? 'change-me';
  const jwt = new JwtService({ secret: jwtSecret });
  const token = await jwt.signAsync({
    sub: user.id,
    email: user.email,
    role: user.role,
    tokenType: 'access',
  });

  const repoRoot = path.resolve(cwd, '..', '..');
  const samplePath = findSampleUploadFile(repoRoot);
  if (!samplePath) {
    throw new Error('No encontré una imagen de prueba en assets/. Sube cualquier jpg/png y lo usamos.');
  }

  const fileName = path.basename(samplePath);
  const mimeType = inferMimeType(fileName);
  const bytes = fs.readFileSync(samplePath);

  console.log(`[e2e] Using user=${user.id} role=${user.role} serviceId=${service.id}`);
  console.log(`[e2e] Sample file: ${samplePath} (${bytes.length} bytes, ${mimeType})`);

  const headers = {
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
  };

  const presign = await httpJson<{
    uploadUrl: string;
    objectKey: string;
    publicUrl: string;
    expiresIn: number;
    mediaType: string;
    mimeType: string;
  }>(`${apiBaseUrl}/storage/presign`, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      serviceId: service.id,
      fileName,
      contentType: mimeType,
      kind: 'evidence_final',
      fileSize: bytes.length,
    }),
  });

  console.log('[e2e] presign ok:', {
    objectKey: presign.objectKey,
    publicUrl: presign.publicUrl,
    expiresIn: presign.expiresIn,
  });

  const putRes = await fetch(presign.uploadUrl, {
    method: 'PUT',
    headers: {
      'Content-Type': mimeType,
    },
    body: bytes,
  });

  const putText = await putRes.text();
  console.log(`[e2e] PUT -> ${putRes.status} ${putRes.statusText}`);
  if (!putRes.ok) {
    throw new Error(`PUT failed: ${putRes.status} ${putRes.statusText}: ${putText.slice(0, 700)}`);
  }

  // Direct HEAD against R2 to verify object exists.
  const endpoint = (process.env.R2_ENDPOINT ?? process.env.R2_S3_ENDPOINT ?? process.env.CLOUDFLARE_R2_ENDPOINT ?? '').trim();
  const bucket = (process.env.R2_BUCKET ?? process.env.R2_BUCKET_NAME ?? '').trim();
  const accessKeyId = (process.env.R2_ACCESS_KEY_ID ?? process.env.AWS_ACCESS_KEY_ID ?? '').trim();
  const secretAccessKey = (process.env.R2_SECRET_ACCESS_KEY ?? process.env.AWS_SECRET_ACCESS_KEY ?? '').trim();
  const region = (process.env.R2_REGION ?? 'auto').trim() || 'auto';

  if (!endpoint || !bucket || !accessKeyId || !secretAccessKey) {
    throw new Error('Faltan env vars R2_* para verificar el objeto en bucket con HEAD.');
  }

  const s3 = new S3Client({
    region,
    endpoint,
    credentials: { accessKeyId, secretAccessKey },
    forcePathStyle: true,
  });

  const head = (await s3.send(
    new HeadObjectCommand({
      Bucket: bucket,
      Key: presign.objectKey,
    }),
  )) as HeadObjectCommandOutput;

  console.log('[e2e] R2 HEAD ok:', {
    contentLength: head.ContentLength,
    contentType: head.ContentType,
    etag: head.ETag,
    lastModified: head.LastModified,
  });

  const confirmed = await httpJson<any>(`${apiBaseUrl}/storage/confirm`, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      serviceId: service.id,
      objectKey: presign.objectKey,
      publicUrl: presign.publicUrl,
      fileName,
      mimeType,
      fileSize: bytes.length,
      kind: 'evidence_final',
      caption: 'e2e-test',
    }),
  });

  console.log('[e2e] confirm ok:', {
    id: confirmed.id,
    objectKey: confirmed.objectKey,
    fileUrl: confirmed.fileUrl,
    caption: confirmed.caption,
    createdAt: confirmed.createdAt,
  });

  const listed = await httpJson<any[]>(`${apiBaseUrl}/storage/service/${service.id}`, {
    method: 'GET',
    headers: { Authorization: `Bearer ${token}` },
  });

  const found = listed.find((x) => x && x.objectKey === presign.objectKey);
  console.log('[e2e] list count:', listed.length);
  console.log('[e2e] listed contains object:', !!found);

  await prisma.$disconnect();
}

main().catch((e) => {
  console.error('[e2e] FAILED:', e);
  process.exit(1);
});
