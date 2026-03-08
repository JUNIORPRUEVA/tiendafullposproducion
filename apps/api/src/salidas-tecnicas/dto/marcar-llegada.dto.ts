import { Type } from 'class-transformer';
import { IsNotEmpty, IsNumber, IsOptional, IsString } from 'class-validator';

export class MarcarLlegadaDto {
  @Type(() => Number)
  @IsNumber()
  latLlegada!: number;

  @Type(() => Number)
  @IsNumber()
  lngLlegada!: number;

  @IsOptional()
  @IsString()
  @IsNotEmpty()
  observacion?: string;
}
