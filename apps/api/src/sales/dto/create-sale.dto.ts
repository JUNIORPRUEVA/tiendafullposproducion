import { IsInt, IsNumber, IsOptional, IsString, IsUUID, Min } from 'class-validator';

export class CreateSaleDto {
  @IsOptional()
  @IsUUID()
  clientId?: string;

  @IsOptional()
  @IsUUID()
  productId?: string;

  @IsOptional()
  @IsInt()
  @Min(1)
  cantidad?: number;

  @IsNumber()
  @Min(0)
  totalVenta!: number;

  @IsOptional()
  @IsNumber()
  puntosUtilidad?: number;

  // Intentionally ignored: userId always comes from JWT token.
  // Kept here only to avoid request rejection when clients send it.
  @IsOptional()
  @IsString()
  userId?: string;
}

