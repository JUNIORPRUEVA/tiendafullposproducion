import { IsBoolean, IsNotEmpty, IsNumber, IsOptional, IsString, Min } from 'class-validator';

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

  @IsNumber()
  @Min(0.01)
  rendimientoKmLitro!: number;

  // fuerza vehículo propio
  @IsOptional()
  @IsBoolean()
  esEmpresa?: boolean;
}
