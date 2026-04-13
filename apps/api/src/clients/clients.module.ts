import { Module } from '@nestjs/common';
import { ProductsModule } from '../products/products.module';
import { ClientsService } from './clients.service';
import { ClientsController } from './clients.controller';

@Module({
  imports: [ProductsModule],
  providers: [ClientsService],
  controllers: [ClientsController]
})
export class ClientsModule {}

