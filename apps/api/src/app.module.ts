import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
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

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: '.env'
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
    OperationsModule
  ]
})
export class AppModule {}

