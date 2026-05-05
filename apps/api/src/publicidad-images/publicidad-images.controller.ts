import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Req,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { memoryStorage } from 'multer';
import { extname } from 'node:path';
import type { Request } from 'express';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { JwtUser } from '../auth/jwt-user.type';
import { PublicidadImagesService } from './publicidad-images.service';

const allowedImageMimes = new Set([
  'image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/heic',
]);
const allowedImageExts = new Set(['.jpg', '.jpeg', '.png', '.webp', '.gif', '.heic']);

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('publicidad-images')
export class PublicidadImagesController {
  constructor(private readonly service: PublicidadImagesService) {}

  @Get()
  @Roles(Role.ADMIN)
  findAll() {
    return this.service.findAll();
  }

  /** Create a record with an already-hosted URL (no file upload). */
  @Post()
  @Roles(Role.ADMIN)
  create(
    @Body() data: { url: string; caption?: string },
    @Req() req: Request,
  ) {
    const user = req.user as unknown as JwtUser;
    return this.service.create({ ...data, uploadedById: user.sub });
  }

  /** Multipart file upload — saves locally and optionally mirrors to R2. */
  @Post('upload')
  @Roles(Role.ADMIN)
  @UseInterceptors(
    FileInterceptor('file', {
      storage: memoryStorage(),
      fileFilter: (
        _req: Express.Request,
        file: Express.Multer.File,
        cb: (error: Error | null, acceptFile: boolean) => void,
      ) => {
        const mime = (file.mimetype ?? '').toLowerCase();
        const ext = extname((file.originalname ?? '').toLowerCase());
        const ok =
          allowedImageMimes.has(mime) ||
          allowedImageExts.has(ext) ||
          mime === 'application/octet-stream';
        if (ok) {
          cb(null, true);
        } else {
          cb(new BadRequestException('Tipo de archivo no permitido. Solo imagenes.'), false);
        }
      },
      limits: { fileSize: 15 * 1024 * 1024 },
    }),
  )
  async uploadFile(
    @Req() req: Request,
    @UploadedFile() file: Express.Multer.File,
    @Body('caption') caption?: string,
  ) {
    if (!file) throw new BadRequestException('No se adjunto ningun archivo');
    const user = req.user as unknown as JwtUser;
    return this.service.createFromFile({
      buffer: file.buffer,
      originalname: file.originalname,
      mimetype: file.mimetype,
      size: file.size,
      caption,
      uploadedById: user.sub,
      req,
    });
  }

  @Patch(':id')
  @Roles(Role.ADMIN)
  update(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() data: { caption?: string },
  ) {
    return this.service.update(id, data);
  }

  @Delete(':id')
  @Roles(Role.ADMIN)
  delete(@Param('id', ParseUUIDPipe) id: string) {
    return this.service.delete(id);
  }
}
