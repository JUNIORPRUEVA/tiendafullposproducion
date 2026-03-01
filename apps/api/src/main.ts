import 'reflect-metadata';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as express from 'express';
import type { Request, Response, NextFunction } from 'express';
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestExpressApplication } from '@nestjs/platform-express';
import { AppModule } from './app.module';
import { GlobalExceptionFilter } from './common/filters/global-exception.filter';

async function bootstrap() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule, { cors: false });
  app.set('trust proxy', 1);

  // Basic request logging (method/url/status/duration).
  app.use((req: Request, res: Response, next: NextFunction) => {
    const start = Date.now();
    const method = req.method;
    const url = req.originalUrl || req.url;

    res.on('finish', () => {
      const durationMs = Date.now() - start;
      const status = res.statusCode;
      // eslint-disable-next-line no-console
      console.log(`[req] ${method} ${url} -> ${status} (${durationMs}ms)`);
    });

    next();
  });

  const config = app.get(ConfigService);

  // Global exception filter: logs errors (incl. Prisma meta) and returns safe JSON.
  app.useGlobalFilters(new GlobalExceptionFilter());
  const port = Number(config.get('PORT') ?? 4000);
  const corsOrigin = config.get<string>('CORS_ORIGIN') ?? 'http://localhost:3000';
  const allowedOrigins = corsOrigin
    .split(',')
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
  const uploadDirEnv = (config.get<string>('UPLOAD_DIR') ?? '').trim();
  const volumeDir = '/uploads';
  const volumeExists = fs.existsSync(volumeDir);
  const uploadDir = uploadDirEnv.length > 0
    ? ((uploadDirEnv === './uploads' || uploadDirEnv === 'uploads') && volumeExists
        ? volumeDir
        : uploadDirEnv)
    : (volumeExists ? volumeDir : path.join(process.cwd(), 'uploads'));

  fs.mkdirSync(uploadDir, { recursive: true });
  app.use('/uploads', express.static(uploadDir));
  // eslint-disable-next-line no-console
  console.log(`[uploads] serving static files from: ${uploadDir}`);

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true
    })
  );

  app.enableCors({
    origin: (origin, callback) => {
      if (!origin || allowedOrigins.includes('*') || allowedOrigins.includes(origin)) {
        callback(null, true);
        return;
      }
      callback(new Error('Not allowed by CORS'));
    },
    credentials: true
  });

  await app.listen(port, '0.0.0.0');
  // eslint-disable-next-line no-console
  console.log(`API listening on http://0.0.0.0:${port}`);
}

bootstrap();

