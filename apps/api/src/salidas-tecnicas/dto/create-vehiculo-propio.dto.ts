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
  placa?: string;

  @IsString()
  @IsNotEmpty()
  combustibleTipo!: string;

  @ValidateIf((o: CreateVehiculoPropioDto) => o.esEmpresa !== true)
  @IsNumber()
  @Min(0.01)
  rendimientoKmLitro?: number;

  // fuerza vehículo propio
  @IsOptional()
  @IsBoolean()
  esEmpresa?: boolean;
}
