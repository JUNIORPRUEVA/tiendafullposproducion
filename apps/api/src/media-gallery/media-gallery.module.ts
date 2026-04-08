import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { MediaGalleryController } from './media-gallery.controller';
import { MediaGalleryService } from './media-gallery.service';

@Module({
  imports: [PrismaModule],
  controllers: [MediaGalleryController],
  providers: [MediaGalleryService],
  exports: [MediaGalleryService],
})
export class MediaGalleryModule {}