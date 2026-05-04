import {
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Query,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { MediaGalleryQueryDto } from './dto/media-gallery-query.dto';
import { MediaGalleryService } from './media-gallery.service';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('media-gallery')
export class MediaGalleryController {
  constructor(private readonly mediaGallery: MediaGalleryService) {}

  @Get()
  @Roles(Role.ADMIN, Role.MARKETING)
  list(@Query() query: MediaGalleryQueryDto) {
    return this.mediaGallery.list(query);
  }

  @Get('publicidad')
  @Roles(Role.ADMIN)
  listPublicidad() {
    return this.mediaGallery.listPublicidad();
  }

  @Patch(':id/publicidad')
  @Roles(Role.ADMIN)
  markForPublicidad(@Param('id', ParseUUIDPipe) id: string) {
    return this.mediaGallery.markForPublicidad(id);
  }

  @Patch(':id/quitar-publicidad')
  @Roles(Role.ADMIN)
  unmarkForPublicidad(@Param('id', ParseUUIDPipe) id: string) {
    return this.mediaGallery.unmarkForPublicidad(id);
  }

  @Delete(':id')
  @Roles(Role.ADMIN)
  deleteEvidence(@Param('id', ParseUUIDPipe) id: string) {
    return this.mediaGallery.deleteEvidence(id);
  }
}