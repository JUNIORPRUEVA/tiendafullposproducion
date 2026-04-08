import { Controller, Get, Query, UseGuards } from '@nestjs/common';
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
}