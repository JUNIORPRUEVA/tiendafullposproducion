import { IsBoolean, IsNotEmpty, IsNumber, IsOptional, IsString, Min, ValidateIf } from 'class-validator';

export class CreateVehiculoPropioDto {
  @IsString()
  @IsNotEmpty()
  nombre!: string;

  @IsString()
  @IsNotEmpty()
  tipo!: string;

  @IsOptional()
  @IsString()
  marca?: string;

  @IsOptional()
  @IsString()
  modelo?: string;

  @IsOptional()
  @IsString()
  placa?: string;

  @IsString()
  @IsNotEmpty()
  combustibleTipo!: string;

  @ValidateIf((o: CreateVehiculoPropioDto) => o.esEmpresa !== true)
  @IsNumber()
  @Min(0.01)
  rendimientoKmLitro?: number;

  @IsOptional()
  @IsNumber()
  @Min(0.01)
  capacidadTanqueLitros?: number;

  // fuerza vehículo propio
  @IsOptional()
  @IsBoolean()
  esEmpresa?: boolean;
}
