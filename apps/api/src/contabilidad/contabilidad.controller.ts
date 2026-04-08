import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Post,
  Put,
  Query,
  Req,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import type { Request } from 'express';
import { memoryStorage } from 'multer';
import { randomUUID } from 'node:crypto';
import { extname, join, posix } from 'node:path';
import * as fs from 'node:fs';
import { AuthGuard } from '@nestjs/passport';
import { RolesGuard } from '../auth/roles.guard';
import { Roles } from '../auth/roles.decorator';
import { R2Service } from '../storage/r2.service';
import { sanitizeFileName } from '../storage/helpers/storage_helpers';
import { ContabilidadService } from './contabilidad.service';
import { CreateCloseDto, UpdateCloseDto } from './close.dto';
import {
  CreateDepositOrderDto,
  DepositOrdersQueryDto,
  UpdateDepositOrderDto,
} from './deposit-order.dto';
import {
  CreateFiscalInvoiceDto,
  FiscalInvoicesQueryDto,
  UpdateFiscalInvoiceDto,
} from './fiscal-invoice.dto';
import {
  CreatePayableServiceDto,
  PayablePaymentsQueryDto,
  PayableServicesQueryDto,
  RegisterPayablePaymentDto,
  UpdatePayableServiceDto,
} from './payable.dto';

type RequestActor = { id?: string; role?: 'ADMIN' | 'ASISTENTE' };

@Controller('contabilidad')
@UseGuards(AuthGuard('jwt'), RolesGuard)
export class ContabilidadController {
  constructor(
    private readonly contabilidadService: ContabilidadService,
    private readonly r2: R2Service,
  ) {}

  @Post('closes')
  @Roles('ADMIN', 'ASISTENTE')
  async createClose(@Body() dto: CreateCloseDto, @Req() req: Request) {
    return this.contabilidadService.createClose(dto, (req.user ?? {}) as RequestActor);
  }

  @Get('closes')
  @Roles('ADMIN', 'ASISTENTE')
  async getCloses(
    @Query('date') date?: string,
    @Query('from') from?: string,
    @Query('to') to?: string,
    @Query('type') type?: string,
  ) {
    return this.contabilidadService.getCloses({ date, from, to, type });
  }

  @Get('closes/:id')
  @Roles('ADMIN', 'ASISTENTE')
  async getCloseById(@Param('id') id: string) {
    return this.contabilidadService.getCloseById(id);
  }

  @Put('closes/:id')
  @Roles('ADMIN', 'ASISTENTE')
  async updateClose(@Param('id') id: string, @Body() dto: UpdateCloseDto, @Req() req: Request) {
    return this.contabilidadService.updateClose(id, dto, (req.user ?? {}) as RequestActor);
  }

  @Delete('closes/:id')
  @Roles('ADMIN', 'ASISTENTE')
  async deleteClose(@Param('id') id: string, @Req() req: Request) {
    return this.contabilidadService.deleteClose(id, (req.user ?? {}) as RequestActor);
  }

  @Post('deposit-orders')
  @Roles('ADMIN', 'ASISTENTE')
  async createDepositOrder(
    @Body() dto: CreateDepositOrderDto,
    @Req() req: Request,
  ) {
    return this.contabilidadService.createDepositOrder(
      dto,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Get('deposit-orders')
  @Roles('ADMIN', 'ASISTENTE')
  async getDepositOrders(@Query() query: DepositOrdersQueryDto) {
    return this.contabilidadService.getDepositOrders(query);
  }

  @Get('deposit-orders/:id')
  @Roles('ADMIN', 'ASISTENTE')
  async getDepositOrderById(@Param('id') id: string) {
    return this.contabilidadService.getDepositOrderById(id);
  }

  @Put('deposit-orders/:id')
  @Roles('ADMIN')
  async updateDepositOrder(
    @Param('id') id: string,
    @Body() dto: UpdateDepositOrderDto,
    @Req() req: Request,
  ) {
    return this.contabilidadService.updateDepositOrder(
      id,
      dto,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Delete('deposit-orders/:id')
  @Roles('ADMIN')
  async deleteDepositOrder(@Param('id') id: string, @Req() req: Request) {
    return this.contabilidadService.deleteDepositOrder(
      id,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Post('deposit-orders/:id/voucher')
  @Roles('ADMIN')
  @UseInterceptors(
    FileInterceptor('file', {
      storage: memoryStorage(),
      fileFilter: (_req, file, cb) => {
        const isAllowed =
          /^image\/(png|jpe?g|webp)$/.test(file.mimetype) ||
          file.mimetype === 'application/pdf';
        if (!isAllowed) {
          return cb(
            new BadRequestException('Solo se permiten voucher en PNG/JPG/WEBP/PDF'),
            false,
          );
        }
        cb(null, true);
      },
      limits: { fileSize: 10 * 1024 * 1024 },
    }),
  )
  async uploadDepositVoucher(
    @Param('id') id: string,
    @Req() req: Request,
    @UploadedFile() file?: Express.Multer.File,
  ) {
    if (!file) throw new BadRequestException('No se subió ningún voucher');
    if (!file.buffer?.length) {
      throw new BadRequestException('No se pudo leer el voucher subido');
    }

    const original = sanitizeFileName(file.originalname ?? 'voucher-deposito');
    const ext = extname(original).toLowerCase();
    const safeExt = ext && /\.(png|jpe?g|webp|pdf)$/.test(ext)
      ? ext
      : file.mimetype === 'application/pdf'
        ? '.pdf'
        : '.jpg';
    const contentType =
      /^image\/(png|jpe?g|webp)$/.test(file.mimetype) || file.mimetype === 'application/pdf'
        ? file.mimetype
        : safeExt === '.png'
          ? 'image/png'
          : safeExt === '.webp'
            ? 'image/webp'
            : safeExt === '.pdf'
              ? 'application/pdf'
              : 'image/jpeg';

    const actor = (req.user ?? {}) as RequestActor;
    const ownerSegment = (actor.id ?? 'anon').trim() || 'anon';
    const now = new Date();
    const month = String(now.getUTCMonth() + 1).padStart(2, '0');
    const baseName = original.replace(/\.[^/.]+$/, '') || 'voucher';
    const objectKey = `contabilidad/deposit-orders/${now.getUTCFullYear()}/${month}/${ownerSegment}/${randomUUID()}-${baseName}${safeExt}`
      .replace(/\s+/g, '_')
      .replace(/[^a-zA-Z0-9/_\-.]/g, '');

    const uploadDirEnv = (process.env['UPLOAD_DIR'] ?? '').trim();
    const volumeDir = '/uploads';
    const volumeExists = fs.existsSync(volumeDir);
    const uploadDir = uploadDirEnv.length > 0
      ? ((uploadDirEnv === './uploads' || uploadDirEnv === 'uploads') && volumeExists
          ? volumeDir
          : uploadDirEnv)
      : (volumeExists ? volumeDir : join(process.cwd(), 'uploads'));

    const relativePath = `/${posix.join('uploads', objectKey)}`;
    const segments = objectKey.split('/');
    const absoluteFilePath = join(uploadDir, ...segments);
    const absoluteDir = join(uploadDir, ...segments.slice(0, -1));

    fs.mkdirSync(absoluteDir, { recursive: true });
    fs.writeFileSync(absoluteFilePath, file.buffer);

    const host = (req.get('host') ?? '').trim();
    const protocol = (req.protocol ?? 'https').trim();
    const url = host ? `${protocol}://${host}${relativePath}` : relativePath;

    try {
      await this.r2.putObject({
        objectKey: `uploads/${objectKey}`,
        body: file.buffer,
        contentType,
      });
    } catch (r2Err) {
      // eslint-disable-next-line no-console
      console.warn('[deposit-orders/voucher] R2 mirror failed, local file is used:', r2Err);
    }

    return this.contabilidadService.attachDepositOrderVoucher(
      id,
      {
        voucherUrl: url,
        voucherFileName: original,
        voucherMimeType: contentType,
      },
      actor,
    );
  }

  @Post('fiscal-invoices/upload')
  @Roles('ADMIN', 'ASISTENTE')
  @UseInterceptors(
    FileInterceptor('file', {
      storage: memoryStorage(),
      fileFilter: (_req, file, cb) => {
        const isImage = /^image\/(png|jpe?g|webp)$/.test(file.mimetype);
        if (!isImage) {
          return cb(
            new BadRequestException('Solo se permiten imágenes PNG/JPG/WEBP'),
            false,
          );
        }
        cb(null, true);
      },
      limits: { fileSize: 8 * 1024 * 1024 },
    }),
  )
  async uploadFiscalInvoiceImage(
    @Req() req: Request,
    @UploadedFile() file?: Express.Multer.File,
  ) {
    if (!file) throw new BadRequestException('No se subió ningún archivo');
    if (!file.buffer?.length) {
      throw new BadRequestException('No se pudo leer la imagen subida');
    }

    const original = sanitizeFileName(file.originalname ?? 'factura');
    const ext = extname(original).toLowerCase();
    const safeExt = ext && /\.(png|jpe?g|webp)$/.test(ext) ? ext : '.jpg';
    const contentType = /^image\/(png|jpe?g|webp)$/.test(file.mimetype)
      ? file.mimetype
      : safeExt === '.png'
        ? 'image/png'
        : safeExt === '.webp'
          ? 'image/webp'
          : 'image/jpeg';

    const actor = (req.user ?? {}) as RequestActor;
    const ownerSegment = (actor.id ?? 'anon').trim() || 'anon';
    const now = new Date();
    const month = String(now.getUTCMonth() + 1).padStart(2, '0');
    const baseName = original.replace(/\.[^/.]+$/, '') || 'factura';
    const objectKey = `contabilidad/fiscal-invoices/${now.getUTCFullYear()}/${month}/${ownerSegment}/${randomUUID()}-${baseName}${safeExt}`
      .replace(/\s+/g, '_')
      .replace(/[^a-zA-Z0-9/_\-.]/g, '');

    // Resolve local upload directory (same logic as main.ts / StorageController).
    const uploadDirEnv = (process.env['UPLOAD_DIR'] ?? '').trim();
    const volumeDir = '/uploads';
    const volumeExists = fs.existsSync(volumeDir);
    const uploadDir = uploadDirEnv.length > 0
      ? ((uploadDirEnv === './uploads' || uploadDirEnv === 'uploads') && volumeExists
          ? volumeDir
          : uploadDirEnv)
      : (volumeExists ? volumeDir : join(process.cwd(), 'uploads'));

    const relativePath = `/${posix.join('uploads', objectKey)}`;
    const segments = objectKey.split('/');
    const absoluteFilePath = join(uploadDir, ...segments);
    const absoluteDir = join(uploadDir, ...segments.slice(0, -1));

    fs.mkdirSync(absoluteDir, { recursive: true });
    fs.writeFileSync(absoluteFilePath, file.buffer);

    // Build a full absolute URL the Flutter app can reach.
    const host = (req.get('host') ?? '').trim();
    const protocol = (req.protocol ?? 'https').trim();
    const url = host
      ? `${protocol}://${host}${relativePath}`
      : relativePath;

    // Optional R2 mirror — failure is non-fatal.
    try {
      await this.r2.putObject({
        objectKey: `uploads/${objectKey}`,
        body: file.buffer,
        contentType,
      });
    } catch (r2Err) {
      // eslint-disable-next-line no-console
      console.warn('[fiscal-invoices/upload] R2 mirror failed, local file is used:', r2Err);
    }

    return {
      fileName: original,
      objectKey,
      url,
    };
  }

  @Post('fiscal-invoices')
  @Roles('ADMIN', 'ASISTENTE')
  async createFiscalInvoice(
    @Body() dto: CreateFiscalInvoiceDto,
    @Req() req: Request,
  ) {
    return this.contabilidadService.createFiscalInvoice(
      dto,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Get('fiscal-invoices')
  @Roles('ADMIN', 'ASISTENTE')
  async getFiscalInvoices(@Query() query: FiscalInvoicesQueryDto) {
    return this.contabilidadService.getFiscalInvoices(query);
  }

  @Put('fiscal-invoices/:id')
  @Roles('ADMIN', 'ASISTENTE')
  async updateFiscalInvoice(
    @Param('id') id: string,
    @Body() dto: UpdateFiscalInvoiceDto,
    @Req() req: Request,
  ) {
    return this.contabilidadService.updateFiscalInvoice(
      id,
      dto,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Delete('fiscal-invoices/:id')
  @Roles('ADMIN', 'ASISTENTE')
  async deleteFiscalInvoice(@Param('id') id: string, @Req() req: Request) {
    return this.contabilidadService.deleteFiscalInvoice(
      id,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Post('payables/services')
  @Roles('ADMIN', 'ASISTENTE')
  async createPayableService(
    @Body() dto: CreatePayableServiceDto,
    @Req() req: Request,
  ) {
    return this.contabilidadService.createPayableService(
      dto,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Get('payables/services')
  @Roles('ADMIN', 'ASISTENTE')
  async getPayableServices(@Query() query: PayableServicesQueryDto) {
    return this.contabilidadService.getPayableServices(query);
  }

  @Put('payables/services/:id')
  @Roles('ADMIN', 'ASISTENTE')
  async updatePayableService(
    @Param('id') id: string,
    @Body() dto: UpdatePayableServiceDto,
    @Req() req: Request,
  ) {
    return this.contabilidadService.updatePayableService(
      id,
      dto,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Post('payables/services/:id/payments')
  @Roles('ADMIN', 'ASISTENTE')
  async registerPayablePayment(
    @Param('id') id: string,
    @Body() dto: RegisterPayablePaymentDto,
    @Req() req: Request,
  ) {
    return this.contabilidadService.registerPayablePayment(
      id,
      dto,
      (req.user ?? {}) as RequestActor,
    );
  }

  @Get('payables/payments')
  @Roles('ADMIN', 'ASISTENTE')
  async getPayablePayments(@Query() query: PayablePaymentsQueryDto) {
    return this.contabilidadService.getPayablePayments(query);
  }
}