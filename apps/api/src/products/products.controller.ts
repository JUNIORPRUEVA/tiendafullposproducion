import { BadRequestException, Body, Controller, Delete, Get, Param, Patch, Post, Req, UploadedFile, UseGuards, UseInterceptors } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { diskStorage } from 'multer';
import { extname, join } from 'node:path';
import type { Express, Request } from 'express';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { CreateProductDto } from './dto/create-product.dto';
import { UpdateProductDto } from './dto/update-product.dto';
import { ProductCostInterceptor } from './product-cost.interceptor';
import { ProductsService } from './products.service';
import { FileInterceptor } from '@nestjs/platform-express';
import * as fs from 'node:fs';

@UseInterceptors(ProductCostInterceptor)
@Controller('products')
export class ProductsController {
  private readonly uploadDir: string;
  private readonly publicBaseUrl: string;

  private resolveUploadDir(config: ConfigService): string {
    const fromEnv = (config.get<string>('UPLOAD_DIR') ?? '').trim();
    const volumeDir = '/uploads';
    const volumeExists = fs.existsSync(volumeDir);

    if (fromEnv.length > 0) {
      if ((fromEnv == './uploads' || fromEnv == 'uploads') && volumeExists) {
        return volumeDir;
      }
      return fromEnv;
    }

    if (volumeExists) return volumeDir;
    return join(process.cwd(), 'uploads');
  }

  constructor(private readonly products: ProductsService, config: ConfigService) {
    const dir = this.resolveUploadDir(config);
    this.uploadDir = dir.trim();
    const base = config.get<string>('PUBLIC_BASE_URL') ?? config.get<string>('API_BASE_URL') ?? '';
    this.publicBaseUrl = base.trim().replace(/\/$/, '');
    fs.mkdirSync(this.uploadDir, { recursive: true });
  }

  @UseGuards(AuthGuard('jwt'))
  @Get()
  findAll() {
    return this.products.findAll();
  }

  @UseGuards(AuthGuard('jwt'))
  @Get(':id')
  findOne(@Param('id') id: string) {
    return this.products.findOne(id);
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Roles(Role.ADMIN, Role.ASISTENTE)
  @Post()
  create(@Body() dto: CreateProductDto) {
    return this.products.create(dto);
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Roles(Role.ADMIN, Role.ASISTENTE)
  @Post('upload')
  @UseInterceptors(
    FileInterceptor('file', {
      storage: diskStorage({
        destination: (_req: Express.Request, _file: Express.Multer.File, cb: (error: Error | null, destination: string) => void) => {
          const fromEnv = (process.env.UPLOAD_DIR ?? '').trim();
          const volumeDir = '/uploads';
          const volumeExists = fs.existsSync(volumeDir);
          const dir = fromEnv.length > 0
            ? ((fromEnv == './uploads' || fromEnv == 'uploads') && volumeExists ? volumeDir : fromEnv)
            : (volumeExists ? volumeDir : join(process.cwd(), 'uploads'));
          fs.mkdirSync(dir, { recursive: true });
          cb(null, dir);
        },
        filename: (_req: Express.Request, file: Express.Multer.File, cb: (error: Error | null, filename: string) => void) => {
          const unique = `${Date.now()}-${Math.round(Math.random() * 1e6)}`;
          cb(null, `${unique}${extname(file.originalname)}`);
        }
      }),
      fileFilter: (_req: Express.Request, file: Express.Multer.File, cb: (error: Error | null, acceptFile: boolean) => void) => {
        const isImage = /^image\/(png|jpe?g|webp)$/.test(file.mimetype);
        if (!isImage) return cb(new BadRequestException('Solo se permiten imágenes PNG/JPG/WEBP'), false);
        cb(null, true);
      },
      limits: { fileSize: 5 * 1024 * 1024 }
    })
  )
  upload(@Req() req: Request, @UploadedFile() file?: Express.Multer.File) {
    if (!file) throw new BadRequestException('No se subió ningún archivo');
    const relativePath = `/uploads/${file.filename}`;
    const proto = (req.get('x-forwarded-proto') ?? req.protocol ?? 'http').split(',')[0].trim();
    const host = (req.get('x-forwarded-host') ?? req.get('host') ?? '').split(',')[0].trim();
    const requestBase = host ? `${proto}://${host}` : '';
    const baseUrl = this.publicBaseUrl || requestBase;
    const url = baseUrl ? `${baseUrl}${relativePath}` : relativePath;
    // eslint-disable-next-line no-console
    console.log(`[products/upload] saved file=${file.filename} path=${relativePath} url=${url}`);
    return { filename: file.filename, path: relativePath, url };
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Roles(Role.ADMIN, Role.ASISTENTE)
  @Patch(':id')
  update(@Param('id') id: string, @Body() dto: UpdateProductDto) {
    return this.products.update(id, dto);
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Roles(Role.ADMIN, Role.ASISTENTE)
  @Delete(':id')
  remove(@Param('id') id: string) {
    return this.products.remove(id);
  }
}

