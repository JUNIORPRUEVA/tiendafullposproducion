import { Role } from '@prisma/client';
import { IsBoolean, IsEnum, IsInt, IsOptional, IsString, MinLength } from 'class-validator';

export class UpdateUserDto {
  @IsOptional()
  @IsString()
  @MinLength(8)
  password?: string;

  @IsOptional()
  @IsString()
  nombreCompleto?: string;

  @IsOptional()
  @IsString()
  telefono?: string;

  @IsOptional()
  @IsInt()
  edad?: number;

  @IsOptional()
  @IsBoolean()
  tieneHijos?: boolean;

  @IsOptional()
  @IsBoolean()
  estaCasado?: boolean;

  @IsOptional()
  @IsBoolean()
  casaPropia?: boolean;

  @IsOptional()
  @IsBoolean()
  vehiculo?: boolean;

  @IsOptional()
  @IsBoolean()
  licenciaConducir?: boolean;

  @IsOptional()
  @IsEnum(Role)
  role?: Role;

  @IsOptional()
  @IsBoolean()
  blocked?: boolean;
}
