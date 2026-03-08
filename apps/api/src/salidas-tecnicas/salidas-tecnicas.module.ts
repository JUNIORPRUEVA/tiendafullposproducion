import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { OperationsModule } from '../operations/operations.module';
import { SalidasTecnicasService } from './salidas-tecnicas.service';
import { TecnicoVehiculosController } from './tecnico-vehiculos.controller';
import { TecnicoSalidasTecnicasController } from './tecnico-salidas-tecnicas.controller';
import { AdminSalidasTecnicasController } from './admin-salidas-tecnicas.controller';
import { AdminPagosCombustibleController } from './admin-pagos-combustible.controller';

@Module({
  imports: [PrismaModule, OperationsModule],
  controllers: [
    TecnicoVehiculosController,
    TecnicoSalidasTecnicasController,
    AdminSalidasTecnicasController,
    AdminPagosCombustibleController,
  ],
  providers: [SalidasTecnicasService],
  exports: [SalidasTecnicasService],
})
export class SalidasTecnicasModule {}
