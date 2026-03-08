import { IsBoolean, IsNumber, IsOptional, IsString, Min } from 'class-validator';

export class UpdateVehiculoPropioDto {
  @IsOptional()
  @IsString()
  nombre?: string;

  @IsOptional()
  @IsString()
  tipo?: string;

  @IsOptional()
  @IsString()
  placa?: string;

  @IsOptional()
  @IsString()
  combustibleTipo?: string;

  @IsOptional()
  @IsNumber()
  @Min(0.01)
  rendimientoKmLitro?: number;

  @IsOptional()
  @IsBoolean()
  activo?: boolean;
}
