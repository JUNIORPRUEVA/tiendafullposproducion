import { Type } from 'class-transformer';
import { IsArray, IsBoolean, IsNotEmpty, IsNumber, IsOptional, IsString, IsUUID, Min, ValidateNested } from 'class-validator';

export class CreateCotizacionItemDto {
  @IsOptional()
  @IsUUID()
  productId?: string;

  @IsOptional()
  @IsString()
  productName?: string;

  @IsOptional()
  @IsString()
  productImageSnapshot?: string;

  @Type(() => Number)
  @IsNumber()
  @Min(0.0001)
  qty!: number;

  @Type(() => Number)
  @IsNumber()
  @Min(0)
  unitPrice!: number;
}

export class CreateCotizacionDto {
  @IsOptional()
  @IsUUID()
  customerId?: string;

  @IsString()
  @IsNotEmpty()
  customerName!: string;

  @IsString()
  @IsNotEmpty()
  customerPhone!: string;

  @IsOptional()
  @IsString()
  note?: string;

  @IsOptional()
  @IsBoolean()
  includeItbis?: boolean;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  itbisRate?: number;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => CreateCotizacionItemDto)
  items!: CreateCotizacionItemDto[];
}
