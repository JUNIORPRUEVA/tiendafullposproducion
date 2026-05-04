import { NestFactory } from '@nestjs/core';
import { AppModule } from '../src/app.module';
import { WhatsappInboxService } from '../src/whatsapp-inbox/whatsapp-inbox.service';

function readFlag(name: string): boolean {
  return process.argv.includes(name);
}

function readNumberFlag(name: string, fallback: number): number {
  const prefix = `${name}=`;
  const raw = process.argv.find((arg) => arg.startsWith(prefix));
  if (!raw) return fallback;
  const value = Number(raw.slice(prefix.length));
  return Number.isFinite(value) ? value : fallback;
}

async function main() {
  const execute = readFlag('--execute');
  const limit = readNumberFlag('--limit', 100);
  const app = await NestFactory.createApplicationContext(AppModule, {
    logger: ['error', 'warn', 'log'],
  });

  try {
    const service = app.get(WhatsappInboxService);
    const result = await service.auditExistingMedia({ execute, limit });
    console.log(JSON.stringify(result, null, 2));
  } finally {
    await app.close();
  }
}

main().catch((error) => {
  console.error('[audit-whatsapp-media] failed', error);
  process.exitCode = 1;
});
