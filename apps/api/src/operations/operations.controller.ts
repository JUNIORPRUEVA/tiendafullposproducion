import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Put,
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
import { ChangeServiceOrderStateDto } from './dto/change-service-order-state.dto';
import { ChangeServicePhaseDto } from './dto/change-service-phase.dto';
import { ChangeServiceAdminPhaseDto } from './dto/change-service-admin-phase.dto';
import { ChangeServiceAdminStatusDto } from './dto/change-service-admin-status.dto';
import { ScheduleServiceDto } from './dto/schedule-service.dto';
import { AssignServiceDto } from './dto/assign-service.dto';
import { ServiceUpdateDto } from './dto/service-update.dto';
import { CreateWarrantyDto } from './dto/create-warranty.dto';
import { UpdateServiceDto } from './dto/update-service.dto';
import { UpsertExecutionReportDto } from './dto/upsert-execution-report.dto';
import { CreateExecutionChangeDto } from './dto/create-execution-change.dto';
import { OperationsChecklistService } from './operations-checklist.service';
import { CreateServiceChecklistTemplateDto } from './dto/create-service-checklist-template.dto';
import { CreateServiceChecklistItemDto } from './dto/create-service-checklist-item.dto';
import { CheckServiceChecklistItemDto } from './dto/check-service-checklist-item.dto';
import { StorageService } from '../storage/storage.service';
import { CreateServiceSignatureDto } from './dto/create-service-signature.dto';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller()
export class OperationsController {
  private readonly uploadDir: string;
  private readonly publicBaseUrl: string;

  constructor(
    private readonly operations: OperationsService,
    private readonly checklists: OperationsChecklistService,
    private readonly storage: StorageService,
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
  async create(@Req() req: Request, @Body() dto: CreateServiceDto) {
    const user = req.user as { id: string; role: Role };
    const service = await this.operations.create(user, dto);
    await this.checklists.ensureServiceChecklists({
      id: service.id,
      category: service.category,
      currentPhase: service.currentPhase,
    });
    return service;
  }

  @Get('checklist/categories')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR)
  listChecklistCategories() {
    return this.checklists.listCategories();
  }

  @Get('checklist/phases')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR)
  listChecklistPhases() {
    return this.checklists.listPhases();
  }

  @Get('checklist/templates')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR)
  listChecklistTemplates(
    @Query('categoryId') categoryId?: string,
    @Query('phaseId') phaseId?: string,
    @Query('categoryCode') categoryCode?: string,
    @Query('phaseCode') phaseCode?: string,
  ) {
    return this.checklists.listTemplates({ categoryId, phaseId, categoryCode, phaseCode });
  }

  @Post('checklist/template')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR)
  createChecklistTemplate(@Req() req: Request, @Body() dto: CreateServiceChecklistTemplateDto) {
    const user = req.user as { id: string; role: Role };
    return this.checklists.createTemplate(user, dto);
  }

  @Post('checklist/item')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR)
  createChecklistItem(@Req() req: Request, @Body() dto: CreateServiceChecklistItemDto) {
    const user = req.user as { id: string; role: Role };
    return this.checklists.createItem(user, dto);
  }

  @Patch('services/:id')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR)
  update(@Req() req: Request, @Param('id') id: string, @Body() dto: UpdateServiceDto) {
    const user = req.user as { id: string; role: Role };
    return this.operations.update(user, id, dto);
  }

  @Patch('ordenes/:id')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR)
  updateOrderAlias(@Req() req: Request, @Param('id') id: string, @Body() dto: UpdateServiceDto) {
    const user = req.user as { id: string; role: Role };
    return this.operations.update(user, id, dto);
  }

  @Patch('services/:id/status')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  changeStatus(@Req() req: Request, @Param('id') id: string, @Body() dto: ChangeServiceStatusDto) {
    const user = req.user as { id: string; role: Role };
    return this.operations.changeStatus(user, id, dto);
  }

  @Patch('services/:id/order-state')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  changeOrderState(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() dto: ChangeServiceOrderStateDto,
  ) {
    const user = req.user as { id: string; role: Role };
    return this.operations.changeOrderState(user, id, dto);
  }

  @Patch('services/:id/phase')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR)
  changePhase(@Req() req: Request, @Param('id') id: string, @Body() dto: ChangeServicePhaseDto) {
    const user = req.user as { id: string; role: Role };
    return this.operations.changePhase(user, id, dto);
  }

  @Patch('services/:id/admin-phase')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR)
  changeAdminPhase(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() dto: ChangeServiceAdminPhaseDto,
  ) {
    const user = req.user as { id: string; role: Role };
    return this.operations.changeAdminPhase(user, id, dto);
  }

  @Patch('services/:id/admin-status')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR)
  changeAdminStatus(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() dto: ChangeServiceAdminStatusDto,
  ) {
    const user = req.user as { id: string; role: Role };
    return this.operations.changeAdminStatus(user, id, dto);
  }

  @Get('services/:id/phases')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  listPhases(@Req() req: Request, @Param('id') id: string) {
    const user = req.user as { id: string; role: Role };
    return this.operations.listPhases(user, id);
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
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  addUpdate(@Req() req: Request, @Param('id') id: string, @Body() dto: ServiceUpdateDto) {
    const user = req.user as { id: string; role: Role };
    return this.operations.addUpdate(user, id, dto);
  }

  @Get('services/:id/execution-report')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  getExecutionReport(
    @Req() req: Request,
    @Param('id') id: string,
    @Query('technicianId') technicianId?: string,
  ) {
    const user = req.user as { id: string; role: Role };
    return this.operations.getExecutionReport(user, id, technicianId);
  }

  @Get('services/:id/checklists')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  getServiceChecklists(@Req() req: Request, @Param('id') id: string) {
    const user = req.user as { id: string; role: Role };
    return this.checklists.getServiceChecklists(user, id);
  }

  @Patch('checklist/item/:id/check')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  checkServiceChecklistItem(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() dto: CheckServiceChecklistItemDto,
  ) {
    const user = req.user as { id: string; role: Role };
    return this.checklists.checkServiceChecklistItem(user, id, dto);
  }

  @Put('services/:id/execution-report')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  upsertExecutionReport(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() dto: UpsertExecutionReportDto,
  ) {
    const user = req.user as { id: string; role: Role };
    return this.operations.upsertExecutionReport(user, id, dto);
  }

  @Post('services/:id/execution-report/changes')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  addExecutionChange(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() dto: CreateExecutionChangeDto,
  ) {
    const user = req.user as { id: string; role: Role };
    return this.operations.addExecutionChange(user, id, dto);
  }

  @Delete('services/:id/execution-report/changes/:changeId')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  deleteExecutionChange(
    @Req() req: Request,
    @Param('id') id: string,
    @Param('changeId') changeId: string,
  ) {
    const user = req.user as { id: string; role: Role };
    return this.operations.deleteExecutionChange(user, id, changeId);
  }

  @Post('services/:id/files')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
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

  @Post('services/:id/signature')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  @UseInterceptors(
    FileInterceptor('file', {
      fileFilter: (
        _req: Express.Request,
        file: Express.Multer.File,
        cb: (error: Error | null, acceptFile: boolean) => void,
      ) => {
        const allowed = /^image\/(png|jpe?g|webp)$/.test(file.mimetype);
        if (!allowed) {
          return cb(new BadRequestException('La firma debe ser una imagen PNG, JPG o WEBP'), false);
        }
        cb(null, true);
      },
      limits: { fileSize: 6 * 1024 * 1024 },
    }),
  )
  uploadSignature(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() dto: CreateServiceSignatureDto,
    @UploadedFile() file?: Express.Multer.File,
  ) {
    const user = req.user as { id: string; role: Role };
    return this.storage.uploadClientSignature(user, {
      serviceId: id,
      signatureBase64: dto.signatureBase64,
      mimeType: dto.mimeType,
      fileName: dto.fileName,
      signedAt: dto.signedAt,
      fileBuffer: file?.buffer,
      fileMimeType: file?.mimetype,
      fileOriginalName: file?.originalname,
    });
  }

  @Post('services/:id/warranty')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR)
  createWarranty(@Req() req: Request, @Param('id') id: string, @Body() dto: CreateWarrantyDto) {
    const user = req.user as { id: string; role: Role };
    return this.operations.createWarranty(user, id, dto);
  }

  @Delete('services/:id')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR)
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
