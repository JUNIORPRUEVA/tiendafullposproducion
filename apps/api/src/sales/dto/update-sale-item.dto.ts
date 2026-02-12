import { IsInt, IsNumber, IsOptional, Min } from 'class-validator';

export class UpdateSaleItemDto {
  @IsOptional()
  @IsInt()
  @Min(1)
  qty?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  unitPriceSold?: number;
}
