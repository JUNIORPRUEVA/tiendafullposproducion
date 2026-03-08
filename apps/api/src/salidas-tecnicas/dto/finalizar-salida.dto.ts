import { Type } from 'class-transformer';
import { IsNotEmpty, IsNumber, IsOptional, IsString } from 'class-validator';

export class FinalizarSalidaDto {
  @Type(() => Number)
  @IsNumber()
  latFinal!: number;

  @Type(() => Number)
  @IsNumber()
  lngFinal!: number;

  @IsOptional()
  @IsString()
  @IsNotEmpty()
  observacion?: string;
}
