import { IsOptional, IsString } from 'class-validator';

export class CreateClientDto {
  @IsString()
  nombre!: string;

  @IsString()
  telefono!: string;

  @IsOptional()
  @IsString()
  email?: string;

  @IsOptional()
  @IsString()
  direccion?: string;

  @IsOptional()
  @IsString()
  notas?: string;
}

