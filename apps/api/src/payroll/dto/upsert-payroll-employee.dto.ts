import { Type } from 'class-transformer';
import { IsBoolean, IsNumber, IsOptional, IsString, IsUUID, Min } from 'class-validator';

export class UpsertPayrollEmployeeDto {
  @IsOptional()
  @IsUUID()
  id?: string;

  @IsString()
  nombre!: string;

  @IsOptional()
  @IsString()
  telefono?: string;

  @IsOptional()
  @IsString()
  puesto?: string;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  cuotaMinima?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  seguroLeyMonto?: number;

  @IsOptional()
  @Type(() => Boolean)
  @IsBoolean()
  activo?: boolean;
}
