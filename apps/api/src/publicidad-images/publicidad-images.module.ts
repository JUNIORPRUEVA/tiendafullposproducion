import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { StorageModule } from '../storage/storage.module';
import { PublicidadImagesController } from './publicidad-images.controller';
import { PublicidadImagesService } from './publicidad-images.service';

@Module({
  imports: [PrismaModule, StorageModule],
  controllers: [PublicidadImagesController],
  providers: [PublicidadImagesService],
  exports: [PublicidadImagesService],
})
export class PublicidadImagesModule {}
