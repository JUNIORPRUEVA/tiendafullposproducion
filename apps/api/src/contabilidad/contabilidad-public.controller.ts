import {
  BadRequestException,
  Controller,
  Get,
  NotFoundException,
  Query,
  Res,
} from '@nestjs/common';
import type { Response } from 'express';
import * as fs from 'node:fs';
import { join } from 'node:path';
import { lookup as lookupMime } from 'mime-types';
import { R2Service } from '../storage/r2.service';

@Controller('public/contabilidad')
export class ContabilidadPublicController {
  constructor(private readonly r2: R2Service) {}

  @Get('fiscal-invoices/image')
  async getFiscalInvoiceImage(
    @Query('url') rawUrl: string | undefined,
    @Res() res: Response,
  ) {
    final raw = (rawUrl ?? '').trim();
    if (raw.isEmpty) {
      throw new BadRequestException('url es requerido');
    }

    const candidates = this.buildCandidates(raw);

    for (final localRelative in candidates.localPaths) {
      const absolutePath = join(this.resolveUploadDir(), ...localRelative.split('/'));
      if (!fs.existsSync(absolutePath)) continue;

      const contentType = lookupMime(absolutePath) || 'application/octet-stream';
      res.setHeader('Content-Type', contentType);
      res.sendFile(absolutePath);
      return;
    }

    for (final objectKey in candidates.r2Keys) {
      try {
        final object = await this.r2.getObject(objectKey);
        res.setHeader('Content-Type', object.contentType ?? 'application/octet-stream');
        if (object.contentLength != null) {
          res.setHeader('Content-Length', String(object.contentLength));
        }
        res.send(object.body);
        return;
      } catch (_) {
        // Try the next candidate.
      }
    }

    throw new NotFoundException('No se encontró la imagen fiscal');
  }

  ({List<String> localPaths, List<String> r2Keys}) buildCandidates(String raw) {
    final normalized = raw.replaceAll('\\', '/').trim();

    String path = normalized;
    if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
      try {
        path = Uri.parse(normalized).path;
      } catch (_) {
        path = normalized;
      }
    }

    final cleanPath = path.replaceAll(RegExp(r'/+'), '/').trim();
    final noLeadingSlash = cleanPath.replaceFirst(RegExp(r'^/+'), '');
    final noUploadsPrefix = noLeadingSlash.startsWith('uploads/')
        ? noLeadingSlash.substring('uploads/'.length)
        : noLeadingSlash;

    final localPaths = <String>{};
    final r2Keys = <String>{};

    if (noLeadingSlash.startsWith('uploads/')) {
      localPaths.add(noLeadingSlash.substring('uploads/'.length));
      r2Keys.add(noLeadingSlash);
    }

    if (noUploadsPrefix.isNotEmpty) {
      localPaths.add(noUploadsPrefix);
      r2Keys.add(noUploadsPrefix);
      r2Keys.add('uploads/$noUploadsPrefix');
    }

    return (localPaths: localPaths.toList(), r2Keys: r2Keys.toList());
  }

  String resolveUploadDir() {
    const volumeDir = '/uploads';
    const volumeExists = fs.existsSync(volumeDir);
    final uploadDirEnv = (process.env['UPLOAD_DIR'] ?? '').trim();

    if (uploadDirEnv.isNotEmpty) {
      if ((uploadDirEnv == './uploads' || uploadDirEnv == 'uploads') && volumeExists) {
        return volumeDir;
      }
      return uploadDirEnv;
    }

    if (volumeExists) return volumeDir;
    return join(process.cwd(), 'uploads');
  }
}