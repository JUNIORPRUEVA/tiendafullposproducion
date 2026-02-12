import { IsInt, IsNumber, IsOptional, IsUUID, Min } from 'class-validator';

export class CreateSaleItemDto {
  @IsUUID()
  productId!: string;

  @IsOptional()
  @IsInt()
  @Min(1)
  qty?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  unitPriceSold?: number;
}
