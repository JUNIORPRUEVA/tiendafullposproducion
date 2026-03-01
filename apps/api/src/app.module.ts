import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { join } from 'path';
import { PrismaModule } from './prisma/prisma.module';
import { HealthModule } from './health/health.module';
import { AuthModule } from './auth/auth.module';
import { UsersModule } from './users/users.module';
import { ProductsModule } from './products/products.module';
import { ClientsModule } from './clients/clients.module';
import { PunchModule } from './punch/punch.module';
import { ContabilidadModule } from './contabilidad/contabilidad.module';
import { SalesModule } from './sales/sales.module';
import { OperationsModule } from './operations/operations.module';
import { PayrollModule } from './payroll/payroll.module';
import { AdminModule } from './admin/admin.module';
import { SettingsModule } from './settings/settings.module';
import { CotizacionesModule } from './cotizaciones/cotizaciones.module';
import { LocationsModule } from './locations/locations.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: [
        join(process.cwd(), '.env'),
        join(process.cwd(), '..', '.env'),
        join(process.cwd(), '..', '..', '.env'),
      ]
    }),
    PrismaModule,
    HealthModule,
    AuthModule,
    UsersModule,
    ProductsModule,
    ClientsModule,
    PunchModule,
    ContabilidadModule,
    SalesModule,
    OperationsModule,
    PayrollModule,
    AdminModule,
    SettingsModule,
    CotizacionesModule,
    LocationsModule,
  ]
})
export class AppModule {}

