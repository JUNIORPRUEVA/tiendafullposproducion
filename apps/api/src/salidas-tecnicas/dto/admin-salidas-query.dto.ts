import { IsOptional, IsString, IsUUID } from 'class-validator';

export class AdminSalidasQueryDto {
  @IsOptional()
  @IsString()
  from?: string;

  @IsOptional()
  @IsString()
  to?: string;

  @IsOptional()
  @IsString()
  estado?: string;

  @IsOptional()
  @IsUUID()
  tecnicoId?: string;
}
