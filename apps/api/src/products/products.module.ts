import { Module } from '@nestjs/common';
import { CatalogProductsController } from './catalog-products.controller';
import { CatalogProductsService } from './catalog-products.service';
import { ProductsService } from './products.service';
import { ProductsController } from './products.controller';

@Module({
  providers: [ProductsService, CatalogProductsService],
  controllers: [ProductsController, CatalogProductsController]
})
export class ProductsModule {}

