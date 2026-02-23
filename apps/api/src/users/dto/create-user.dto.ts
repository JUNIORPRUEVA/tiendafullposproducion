import { Role } from '@prisma/client';
import { IsBoolean, IsEmail, IsEnum, IsInt, IsOptional, IsString, MinLength } from 'class-validator';

export class CreateUserDto {
  @IsEmail()
  email!: string;

  @IsString()
  @MinLength(8)
  password!: string;

  @IsString()
  nombreCompleto!: string;

  @IsString()
  telefono!: string;

  @IsString()
  telefonoFamiliar!: string;

  @IsString()
  cedula!: string;

  @IsString()
  fotoCedulaUrl!: string;

  @IsOptional()
  @IsString()
  fotoLicenciaUrl?: string;

  @IsOptional()
  @IsString()
  fotoPersonalUrl?: string;

  @IsInt()
  edad!: number;

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

  @IsEnum(Role)
  role!: Role;

  @IsOptional()
  @IsBoolean()
  blocked?: boolean;
}
