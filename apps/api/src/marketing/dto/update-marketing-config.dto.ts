import { IsArray, IsBoolean, IsInt, IsOptional, IsString, Matches, Max, Min } from 'class-validator';

export class UpdateMarketingConfigDto {
  @IsOptional()
  @IsBoolean()
  flujo_activo?: boolean;

  @IsOptional()
  @IsBoolean()
  pausado?: boolean;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(6)
  cantidad_estados_diarios?: number;

  @IsOptional()
  @IsString()
  @Matches(/^([01]\d|2[0-3]):([0-5]\d)$/)
  hora_generacion?: string;

  @IsOptional()
  @IsBoolean()
  auto_regenerar_si_no_aprueba?: boolean;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(72)
  horas_para_regenerar?: number;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  productos_prioritarios?: string[];

  @IsOptional()
  @IsString()
  ciudad_objetivo?: string;

  @IsOptional()
  @IsString()
  tono_de_marca?: string;
}
