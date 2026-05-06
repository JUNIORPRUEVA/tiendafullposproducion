import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  Logger,
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
  'image/jpeg', 'image/png', 'image/webp',
]);
const allowedImageExts = new Set(['.jpg', '.jpeg', '.png', '.webp']);

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('publicidad-images')
export class PublicidadImagesController {
  private readonly logger = new Logger(PublicidadImagesController.name);

  constructor(private readonly service: PublicidadImagesService) {}

  private resolveRequestUserId(req: Request): string {
    const user = req.user as
      | (Partial<JwtUser> & { id?: string; sub?: string })
      | undefined;
    const id = `${user?.id ?? user?.sub ?? ''}`.trim();
    if (!id) {
      throw new BadRequestException('No se pudo resolver el usuario autenticado para la subida');
    }
    return id;
  }

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
    const uploadedById = this.resolveRequestUserId(req);
    return this.service.create({ ...data, uploadedById });
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
    const uploadedById = this.resolveRequestUserId(req);
    this.logger.log(
      `[upload] received request user=${uploadedById} content-type=${req.get('content-type') ?? 'n/a'} filePresent=${Boolean(file)}`,
    );
    if (!file) throw new BadRequestException('No se adjunto ningun archivo');
    this.logger.log(
      `[upload] file detected original=${file.originalname} mime=${file.mimetype} size=${file.size}`,
    );
    const created = await this.service.createFromFile({
      buffer: file.buffer,
      originalname: file.originalname,
      mimetype: file.mimetype,
      size: file.size,
      caption,
      uploadedById,
      req,
    });

    this.logger.log(
      `[upload] success id=${created.id} imageUrl=${created.url}`,
    );

    return {
      success: true,
      id: created.id,
      imageUrl: created.url,
      image: created,
    };
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
