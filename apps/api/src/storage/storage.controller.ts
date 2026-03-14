import { Body, Controller, Delete, Get, Param, Post, Query, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Request } from 'express';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { PresignStorageDto } from './dto/presign.dto';
import { ConfirmStorageDto } from './dto/confirm.dto';
import { StorageService } from './storage.service';
import { ServiceMediaQueryDto } from './dto/service-media-query.dto';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('storage')
export class StorageController {
  constructor(private readonly storage: StorageService) {}

  // Flow for Flutter:
  // 1) POST /storage/presign -> {uploadUrl, objectKey, publicUrl}
  // 2) PUT uploadUrl (direct to R2) with header Content-Type
  // 3) POST /storage/confirm -> record persisted in Postgres
  // 4) GET /storage/service/:serviceId -> gallery/list

  @Post('presign')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  presign(@Req() req: Request, @Body() dto: PresignStorageDto) {
    const user = req.user as { id: string; role: Role };
    return this.storage.presignUpload(user, dto);
  }

  @Post('confirm')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  confirm(@Req() req: Request, @Body() dto: ConfirmStorageDto) {
    const user = req.user as { id: string; role: Role };
    return this.storage.confirmUpload(user, dto);
  }

  @Get('service/:serviceId')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  listByService(
    @Req() req: Request,
    @Param('serviceId') serviceId: string,
    @Query() query: ServiceMediaQueryDto,
  ) {
    const user = req.user as { id: string; role: Role };
    return this.storage.listServiceFiles(user, serviceId, query);
  }

  @Get(':id')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  getOne(@Req() req: Request, @Param('id') id: string) {
    const user = req.user as { id: string; role: Role };
    return this.storage.getFile(user, id);
  }

  @Delete(':id')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO)
  remove(@Req() req: Request, @Param('id') id: string) {
    const user = req.user as { id: string; role: Role };
    return this.storage.deleteFile(user, id);
  }
}
