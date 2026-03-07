import { Controller, Get, Header, UseGuards, UseInterceptors } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { CatalogProductsService } from './catalog-products.service';
import { ProductCostInterceptor } from './product-cost.interceptor';

@UseInterceptors(ProductCostInterceptor)
@Controller('catalog')
export class CatalogProductsController {
  constructor(private readonly catalogProducts: CatalogProductsService) {}

  @UseGuards(AuthGuard('jwt'))
  @Header('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate')
  @Header('Pragma', 'no-cache')
  @Header('Expires', '0')
  @Header('Surrogate-Control', 'no-store')
  @Get('products')
  findAll() {
    return this.catalogProducts.findAll();
  }
}
