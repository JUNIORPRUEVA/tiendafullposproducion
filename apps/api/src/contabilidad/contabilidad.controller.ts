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
import { ConfigService } from '@nestjs/config';
import { FileInterceptor } from '@nestjs/platform-express';
import type { Request } from 'express';
import { diskStorage } from 'multer';
import * as fs from 'node:fs';
import { extname, join } from 'node:path';
import { AuthGuard } from '@nestjs/passport';
import { RolesGuard } from '../auth/roles.guard';
import { Roles } from '../auth/roles.decorator';
import { ContabilidadService } from './contabilidad.service';
import { CreateCloseDto, UpdateCloseDto } from './close.dto';
import {
  CreateDepositOrderDto,
  DepositOrdersQueryDto,
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
  private readonly uploadDir: string;
  private readonly publicBaseUrl: string;

  private resolveUploadDir(config: ConfigService): string {
    const fromEnv = (config.get<string>('UPLOAD_DIR') ?? '').trim();
    const volumeDir = '/uploads';
    const volumeExists = fs.existsSync(volumeDir);

    if (fromEnv.length > 0) {
      if ((fromEnv === './uploads' || fromEnv === 'uploads') && volumeExists) {
        return volumeDir;
      }
      return fromEnv;
    }

    if (volumeExists) return volumeDir;
    return join(process.cwd(), 'uploads');
  }

  constructor(
    private readonly contabilidadService: ContabilidadService,
    config: ConfigService,
  ) {
    this.uploadDir = this.resolveUploadDir(config);
    const base =
      config.get<string>('PUBLIC_BASE_URL') ??
      config.get<string>('API_BASE_URL') ??
      '';
    this.publicBaseUrl = base.trim().replace(/\/$/, '');
    fs.mkdirSync(this.uploadDir, { recursive: true });
  }

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

  @Post('fiscal-invoices/upload')
  @Roles('ADMIN', 'ASISTENTE')
  @UseInterceptors(
    FileInterceptor('file', {
      storage: diskStorage({
        destination: (_req, _file, cb) => {
          const fromEnv = (process.env.UPLOAD_DIR ?? '').trim();
          const volumeDir = '/uploads';
          const volumeExists = fs.existsSync(volumeDir);
          const dir =
            fromEnv.length > 0
              ? ((fromEnv === './uploads' || fromEnv === 'uploads') && volumeExists
                  ? volumeDir
                  : fromEnv)
              : (volumeExists ? volumeDir : join(process.cwd(), 'uploads'));
          fs.mkdirSync(dir, { recursive: true });
          cb(null, dir);
        },
        filename: (_req, file, cb) => {
          const unique = `${Date.now()}-${Math.round(Math.random() * 1e6)}`;
          cb(null, `fiscal-${unique}${extname(file.originalname)}`);
        },
      }),
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
  uploadFiscalInvoiceImage(@Req() req: Request, @UploadedFile() file?: Express.Multer.File) {
    if (!file) throw new BadRequestException('No se subió ningún archivo');
    const relativePath = `/uploads/${file.filename}`;
    const proto = (req.get('x-forwarded-proto') ?? req.protocol ?? 'http')
      .split(',')[0]
      .trim();
    const host = (req.get('x-forwarded-host') ?? req.get('host') ?? '')
      .split(',')[0]
      .trim();
    const requestBase = host ? `${proto}://${host}` : '';
    const baseUrl = this.publicBaseUrl || requestBase;
    const url = baseUrl ? `${baseUrl}${relativePath}` : relativePath;
    return { filename: file.filename, path: relativePath, url };
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