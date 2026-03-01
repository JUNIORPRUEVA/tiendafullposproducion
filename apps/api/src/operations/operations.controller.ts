import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Query,
  Req,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Request } from 'express';
import { diskStorage } from 'multer';
import { extname, join } from 'node:path';
import type { Express } from 'express';
import { FileInterceptor } from '@nestjs/platform-express';
import { ConfigService } from '@nestjs/config';
import * as fs from 'node:fs';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { OperationsService } from './operations-main.service';
import { ServicesQueryDto } from './dto/services-query.dto';
import { CreateServiceDto } from './dto/create-service.dto';
import { ChangeServiceStatusDto } from './dto/change-service-status.dto';
import { ScheduleServiceDto } from './dto/schedule-service.dto';
import { AssignServiceDto } from './dto/assign-service.dto';
import { ServiceUpdateDto } from './dto/service-update.dto';
import { CreateWarrantyDto } from './dto/create-warranty.dto';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller()
export class OperationsController {
  private readonly uploadDir: string;
  private readonly publicBaseUrl: string;

  constructor(
    private readonly operations: OperationsService,
    config: ConfigService,
  ) {
    const dir = config.get<string>('UPLOAD_DIR') ?? join(process.cwd(), 'uploads');
    this.uploadDir = dir.trim();
    const base = config.get<string>('PUBLIC_BASE_URL') ?? config.get<string>('API_BASE_URL') ?? '';
    this.publicBaseUrl = base.trim().replace(/\/$/, '');
    fs.mkdirSync(this.uploadDir, { recursive: true });
  }

  @Get('services')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  list(@Req() req: Request, @Query() query: ServicesQueryDto) {
    const user = req.user as { id: string; role: Role };
    return this.operations.list(user, query);
  }

  @Get('technicians')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  technicians(@Req() req: Request) {
    const user = req.user as { id: string; role: Role };
    return this.operations.listTechnicians(user);
  }

  @Get('services/:id')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  getOne(@Req() req: Request, @Param('id') id: string) {
    const user = req.user as { id: string; role: Role };
    return this.operations.findOne(user, id);
  }

  @Post('services')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR)
  create(@Req() req: Request, @Body() dto: CreateServiceDto) {
    const user = req.user as { id: string; role: Role };
    return this.operations.create(user, dto);
  }

  @Patch('services/:id/status')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  changeStatus(@Req() req: Request, @Param('id') id: string, @Body() dto: ChangeServiceStatusDto) {
    const user = req.user as { id: string; role: Role };
    return this.operations.changeStatus(user, id, dto);
  }

  @Patch('services/:id/schedule')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR)
  schedule(@Req() req: Request, @Param('id') id: string, @Body() dto: ScheduleServiceDto) {
    const user = req.user as { id: string; role: Role };
    return this.operations.schedule(user, id, dto);
  }

  @Post('services/:id/assign')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR)
  assign(@Req() req: Request, @Param('id') id: string, @Body() dto: AssignServiceDto) {
    const user = req.user as { id: string; role: Role };
    return this.operations.assign(user, id, dto);
  }

  @Post('services/:id/update')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR)
  addUpdate(@Req() req: Request, @Param('id') id: string, @Body() dto: ServiceUpdateDto) {
    const user = req.user as { id: string; role: Role };
    return this.operations.addUpdate(user, id, dto);
  }

  @Post('services/:id/files')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR)
  @UseInterceptors(
    FileInterceptor('file', {
      storage: diskStorage({
        destination: (_req: Express.Request, _file: Express.Multer.File, cb: (error: Error | null, destination: string) => void) =>
          cb(null, process.env.UPLOAD_DIR?.trim() || join(process.cwd(), 'uploads')),
        filename: (_req: Express.Request, file: Express.Multer.File, cb: (error: Error | null, filename: string) => void) => {
          const unique = `${Date.now()}-${Math.round(Math.random() * 1e6)}`;
          cb(null, `${unique}${extname(file.originalname)}`);
        },
      }),
      fileFilter: (_req: Express.Request, file: Express.Multer.File, cb: (error: Error | null, acceptFile: boolean) => void) => {
        const allowed = /^image\/(png|jpe?g|webp)$|^application\/(pdf|msword|vnd.openxmlformats-officedocument.wordprocessingml.document)$/.test(file.mimetype);
        if (!allowed) return cb(new BadRequestException('Archivo no permitido'), false);
        cb(null, true);
      },
      limits: { fileSize: 10 * 1024 * 1024 },
    }),
  )
  uploadFile(@Req() req: Request, @Param('id') id: string, @UploadedFile() file?: Express.Multer.File) {
    if (!file) throw new BadRequestException('No se subió ningún archivo');
    const user = req.user as { id: string; role: Role };
    const relativePath = `/uploads/${file.filename}`;
    const url = this.publicBaseUrl ? `${this.publicBaseUrl}${relativePath}` : relativePath;
    return this.operations.addFile(user, id, url, file.mimetype);
  }

  @Post('services/:id/warranty')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR)
  createWarranty(@Req() req: Request, @Param('id') id: string, @Body() dto: CreateWarrantyDto) {
    const user = req.user as { id: string; role: Role };
    return this.operations.createWarranty(user, id, dto);
  }

  @Delete('services/:id')
  @Roles(Role.ADMIN)
  remove(@Req() req: Request, @Param('id') id: string) {
    const user = req.user as { id: string; role: Role };
    return this.operations.remove(user, id);
  }

  @Get('customers/:id/services')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  customerServices(@Req() req: Request, @Param('id') id: string) {
    const user = req.user as { id: string; role: Role };
    return this.operations.servicesByCustomer(user, id);
  }

  @Get('dashboard/operations')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  dashboard(@Req() req: Request, @Query() query: ServicesQueryDto) {
    const user = req.user as { id: string; role: Role };
    return this.operations.dashboard(user, query.from, query.to);
  }
}
