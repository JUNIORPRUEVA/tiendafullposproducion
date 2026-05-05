import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Request,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { PublicidadImagesService } from './publicidad-images.service';

interface AuthRequest extends Request {
  user?: {
    sub: string;
    email: string;
  };
}

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('publicidad-images')
export class PublicidadImagesController {
  constructor(private readonly service: PublicidadImagesService) {}

  @Post()
  @Roles(Role.ADMIN)
  create(
    @Body()
    data: {
      url: string;
      caption?: string;
    },
    @Request() req: AuthRequest,
  ) {
    return this.service.create({
      ...data,
      uploadedById: req.user!.sub,
    });
  }

  @Get()
  @Roles(Role.ADMIN)
  findAll() {
    return this.service.findAll();
  }

  @Post('upload-url')
  @Roles(Role.ADMIN)
  generateUploadUrl(@Body() data: { filename: string }) {
    return this.service.generateUploadUrl(data.filename);
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
