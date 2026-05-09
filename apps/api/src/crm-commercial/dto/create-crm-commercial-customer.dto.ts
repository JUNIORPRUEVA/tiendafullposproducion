import { IsDateString, IsEnum, IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';
import { CrmCommercialCustomerStatus } from '@prisma/client';

export class CreateCrmCommercialCustomerDto {
  @IsString()
  @MaxLength(160)
  nombre!: string;

  @IsString()
  @MaxLength(40)
  telefono!: string;

  @IsOptional()
  @IsString()
  @MaxLength(250)
  direccion?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  ciudad?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  etiqueta?: string;

  @IsOptional()
  @IsUUID()
  clientId?: string;

  @IsOptional()
  @IsUUID()
  responsableUserId?: string;

  @IsOptional()
  @IsEnum(CrmCommercialCustomerStatus)
  estadoActual?: CrmCommercialCustomerStatus;

  @IsOptional()
  @IsDateString()
  nextActionAt?: string;

  @IsOptional()
  @IsString()
  @MaxLength(240)
  nextAction?: string;

  @IsOptional()
  @IsString()
  observacion?: string;
}
