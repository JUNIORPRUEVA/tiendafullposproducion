import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { LocationsController } from './locations.controller';
import { LocationsService } from './locations.service';
import { AdminLocationsController } from './admin-locations.controller';

@Module({
  imports: [PrismaModule],
  controllers: [LocationsController, AdminLocationsController],
  providers: [LocationsService],
})
export class LocationsModule {}
