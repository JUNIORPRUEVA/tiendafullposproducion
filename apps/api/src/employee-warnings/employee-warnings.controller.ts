import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  Put,
  Query,
  Req,
  Res,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { AuthGuard } from '@nestjs/passport';
import type { Request, Response } from 'express';
import { memoryStorage } from 'multer';
import { Role } from '@prisma/client';
import { RolesGuard } from '../auth/roles.guard';
import { Roles } from '../auth/roles.decorator';
import { EmployeeWarningsService } from './employee-warnings.service';
import {
  AnnulEmployeeWarningDto,
  CreateEmployeeWarningDto,
  EmployeeWarningsQueryDto,
  UpdateEmployeeWarningDto,
} from './dto/employee-warning.dto';

type RequestUser = { id?: string; role?: string };

// Roles autorizados a gestionar amonestaciones en el flujo actual.
const AUTHORIZED_ROLES: Role[] = [Role.ADMIN, Role.ASISTENTE];

// ────────────────────────────────────────────────────────────────────────────
// Admin endpoints  →  /employee-warnings
// ────────────────────────────────────────────────────────────────────────────

@Controller('employee-warnings')
@UseGuards(AuthGuard('jwt'), RolesGuard)
export class EmployeeWarningsController {
  constructor(private readonly service: EmployeeWarningsService) {}

  /** List all warnings (admin only) */
  @Get()
  @Roles(...AUTHORIZED_ROLES)
  findAll(@Query() query: EmployeeWarningsQueryDto) {
    return this.service.findAll(query);
  }

  /** Get single warning by id (admin only) */
  @Get(':id')
  @Roles(...AUTHORIZED_ROLES)
  findOne(@Param('id') id: string) {
    return this.service.findOne(id);
  }

  /** Create warning (default: emitted) */
  @Post()
  @Roles(...AUTHORIZED_ROLES)
  create(@Body() dto: CreateEmployeeWarningDto, @Req() req: Request) {
    const actor = req.user as RequestUser;
    return this.service.create(dto, actor.id ?? '');
  }

  /** Update warning (draft only) */
  @Put(':id')
  @Roles(...AUTHORIZED_ROLES)
  update(
    @Param('id') id: string,
    @Body() dto: UpdateEmployeeWarningDto,
    @Req() req: Request,
  ) {
    const actor = req.user as RequestUser;
    return this.service.update(id, dto, actor.id ?? '');
  }

  /** Delete a draft warning */
  @Delete(':id')
  @HttpCode(HttpStatus.OK)
  @Roles(...AUTHORIZED_ROLES)
  deleteDraft(@Param('id') id: string, @Req() req: Request) {
    const actor = req.user as RequestUser;
    return this.service.deleteDraft(id, actor.id ?? '');
  }

  /** Annul an emitted warning */
  @Post(':id/annul')
  @Roles(...AUTHORIZED_ROLES)
  annul(
    @Param('id') id: string,
    @Body() dto: AnnulEmployeeWarningDto,
    @Req() req: Request,
  ) {
    const actor = req.user as RequestUser;
    return this.service.annul(id, dto, actor.id ?? '');
  }

  /** Regenerate PDF for a warning */
  @Post(':id/pdf')
  @Roles(...AUTHORIZED_ROLES)
  generatePdf(@Param('id') id: string, @Req() req: Request) {
    const actor = req.user as RequestUser;
    return this.service.generatePdf(id, actor.id ?? '');
  }

  /** Upload evidence file for a draft warning */
  @Post(':id/evidences')
  @Roles(...AUTHORIZED_ROLES)
  @UseInterceptors(
    FileInterceptor('file', {
      storage: memoryStorage(),
      limits: { fileSize: 10 * 1024 * 1024 }, // 10 MB
    }),
  )
  uploadEvidence(
    @Param('id') id: string,
    @UploadedFile() file: Express.Multer.File,
    @Req() req: Request,
  ) {
    const actor = req.user as RequestUser;
    return this.service.uploadEvidence(
      id,
      { buffer: file.buffer, originalname: file.originalname, mimetype: file.mimetype },
      actor.id ?? '',
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Employee endpoints  →  /employee-warnings/me/…
  // ──────────────────────────────────────────────────────────────────────────

  /** Employee: list their own warnings (read-only) */
  @Get('me/pending')
  myPending(@Req() req: Request) {
    const user = req.user as RequestUser;
    return this.service.findMyPending(user.id ?? '');
  }

  /** Employee: get a specific warning of theirs */
  @Get('me/:id')
  myWarning(@Param('id') id: string, @Req() req: Request) {
    const user = req.user as RequestUser;
    return this.service.findMyWarning(id, user.id ?? '');
  }

  /** Employee: download the warning PDF (served through the API with auth) */
  @Get('me/:id/pdf')
  async getMyPdf(
    @Param('id') id: string,
    @Req() req: Request,
    @Res() res: Response,
  ) {
    const user = req.user as RequestUser;
    const { body, contentType, filename } = await this.service.getMyPdfBytes(
      id,
      user.id ?? '',
    );
    res
      .set({
        'Content-Type': contentType,
        'Content-Disposition': `inline; filename="${filename}"`,
        'Content-Length': body.length,
        'Cache-Control': 'private, max-age=300',
      })
      .send(body);
  }

}
