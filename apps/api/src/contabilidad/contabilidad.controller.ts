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
import { extname } from 'node:path';
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

    await this.r2.putObject({
      objectKey,
      body: file.buffer,
      contentType,
    });

    const url = this.r2.buildPublicUrl(objectKey);
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