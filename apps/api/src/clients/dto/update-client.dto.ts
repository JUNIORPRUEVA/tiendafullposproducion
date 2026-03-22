import { IsOptional, IsString } from 'class-validator';
import { ClientLocationFieldsDto } from './client-location-fields.dto';

export class UpdateClientDto extends ClientLocationFieldsDto {
  @IsOptional()
  @IsString()
  nombre?: string;

  @IsOptional()
  @IsString()
  telefono?: string;

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

