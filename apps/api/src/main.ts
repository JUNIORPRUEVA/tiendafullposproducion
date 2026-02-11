import 'reflect-metadata';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as express from 'express';
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestExpressApplication } from '@nestjs/platform-express';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule, { cors: false });

  const config = app.get(ConfigService);
  const port = Number(config.get('PORT') ?? 4000);
  const corsOrigin = config.get<string>('CORS_ORIGIN') ?? 'http://localhost:3000';
  const uploadDir = (config.get<string>('UPLOAD_DIR') ?? path.join(process.cwd(), 'uploads')).trim();

  fs.mkdirSync(uploadDir, { recursive: true });
  app.use('/uploads', express.static(uploadDir));

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true
    })
  );

  app.enableCors({
    origin: corsOrigin === '*' ? true : corsOrigin,
    credentials: true
  });

  await app.listen(port, '0.0.0.0');
  // eslint-disable-next-line no-console
  console.log(`API listening on http://0.0.0.0:${port}`);
}

bootstrap();

