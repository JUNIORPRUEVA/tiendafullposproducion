import { NestFactory } from '@nestjs/core';
import { AppModule } from '../src/app.module';
import { WhatsappInboxService } from '../src/whatsapp-inbox/whatsapp-inbox.service';

function readRequiredFlag(name: string): string {
  const prefix = `${name}=`;
  const raw = process.argv.find((arg) => arg.startsWith(prefix));
  const value = raw?.slice(prefix.length).trim();
  if (!value) {
    throw new Error(`Falta ${name}=XXXX`);
  }
  return value;
}

async function main() {
  const messageId = readRequiredFlag('--messageId');
  const app = await NestFactory.createApplicationContext(AppModule, {
    logger: ['error', 'warn', 'log'],
  });

  try {
    const service = app.get(WhatsappInboxService);
    const result = await service.debugMediaMessage(messageId);
    console.log(JSON.stringify(result, null, 2));
  } finally {
    await app.close();
  }
}

main().catch((error) => {
  console.error('[debug-whatsapp-media] failed', error);
  process.exitCode = 1;
});