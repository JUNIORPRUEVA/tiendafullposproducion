import { Module } from '@nestjs/common';
import { StorageModule } from '../storage/storage.module';
import { ContabilidadController } from './contabilidad.controller';
import { ContabilidadService } from './contabilidad.service';

@Module({
  imports: [StorageModule],
  controllers: [ContabilidadController],
  providers: [ContabilidadService],
})
export class ContabilidadModule {}