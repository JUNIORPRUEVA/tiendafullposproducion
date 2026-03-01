import { IsOptional, IsString, Max, Min } from 'class-validator';
import { Type } from 'class-transformer';

export class CotizacionesQueryDto {
  @IsOptional()
  @IsString()
  customerPhone?: string;

  @IsOptional()
  @Type(() => Number)
  @Min(1)
  @Max(500)
  take?: number;
}
