import { BadRequestException, Body, Controller, Delete, Get, Param, Patch, Post, Req, UnauthorizedException, UploadedFile, UseGuards, UseInterceptors } from '@nestjs/common';
import { UsersService } from './users.service';
import { AuthGuard } from '@nestjs/passport';
import { Roles } from '../auth/roles.decorator';
import { Role } from '@prisma/client';
import { RolesGuard } from '../auth/roles.guard';
import { CreateUserDto } from './dto/create-user.dto';
import { UpdateUserDto } from './dto/update-user.dto';
import { BlockUserDto } from './dto/block-user.dto';
import { SelfUpdateUserDto } from './dto/self-update-user.dto';
import { Request } from 'express';
import { ConfigService } from '@nestjs/config';
import { FileInterceptor } from '@nestjs/platform-express';
import { diskStorage } from 'multer';
import { extname, join } from 'node:path';
import * as fs from 'node:fs';
import type { Express } from 'express';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('users')
export class UsersController {
  private readonly uploadDir: string;
  private readonly publicBaseUrl: string;

  constructor(private readonly users: UsersService, config: ConfigService) {
    const dir = config.get<string>('UPLOAD_DIR') ?? join(process.cwd(), 'uploads');
    this.uploadDir = dir.trim();
    const base = config.get<string>('PUBLIC_BASE_URL') ?? config.get<string>('API_BASE_URL') ?? '';
    this.publicBaseUrl = base.trim().replace(/\/$/, '');
    fs.mkdirSync(this.uploadDir, { recursive: true });
  }

  @Post('upload')
  // Any authenticated user can upload a profile/document image.
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.MARKETING, Role.VENDEDOR, Role.TECNICO)
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
        const mimetype = (file.mimetype ?? '').toLowerCase().trim();
        const isImageMime = /^image\/(png|jpe?g|webp)$/.test(mimetype);
        if (isImageMime) return cb(null, true);

        // Some clients (desktop/web) may send empty/unknown mimetype. Fallback to file extension.
        const original = (file.originalname ?? '').toLowerCase();
        const hasAllowedExt = /\.(png|jpe?g|webp)$/.test(original);
        const isUnknownMime = mimetype.length === 0 || mimetype === 'application/octet-stream';
        if (isUnknownMime && hasAllowedExt) return cb(null, true);

        return cb(new BadRequestException('Solo se permiten imágenes PNG/JPG/WEBP'), false);
      },
      limits: { fileSize: 10 * 1024 * 1024 }
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
    return { filename: file.filename, path: relativePath, url };
  }

  @Post()
  @Roles(Role.ADMIN)
  create(@Body() dto: CreateUserDto) {
    return this.users.create(dto);
  }

  @Get()
  @Roles(Role.ADMIN)
  findAll() {
    return this.users.findAll();
  }

  @Get(':id/birthday-greeting')
  @Roles(Role.ADMIN)
  birthdayGreeting(@Param('id') id: string) {
    return this.users.generateBirthdayGreeting(id);
  }

  @Get('me')
  me(@Req() req: Request) {
    const user = req.user as { id?: string } | undefined;
    if (!user?.id) {
      throw new UnauthorizedException('Usuario no autenticado');
    }
    return this.users.findById(user.id);
  }

  @Patch('me')
  updateSelf(@Req() req: Request, @Body() dto: SelfUpdateUserDto) {
    const user = req.user as { id?: string } | undefined;
    if (!user?.id) {
      throw new UnauthorizedException('Usuario no autenticado');
    }
    return this.users.updateSelf(user.id, dto);
  }

  @Patch(':id')
  @Roles(Role.ADMIN)
  update(@Param('id') id: string, @Body() dto: UpdateUserDto) {
    return this.users.update(id, dto);
  }

  @Patch(':id/block')
  @Roles(Role.ADMIN)
  setBlocked(@Param('id') id: string, @Body() dto: BlockUserDto) {
    return this.users.setBlocked(id, dto.blocked);
  }

  @Delete(':id')
  @Roles(Role.ADMIN)
  remove(@Param('id') id: string) {
    return this.users.remove(id);
  }
}

