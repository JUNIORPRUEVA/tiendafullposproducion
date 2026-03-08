import { IsOptional, IsString } from 'class-validator';

export class SalidasQueryDto {
  @IsOptional()
  @IsString()
  from?: string;

  @IsOptional()
  @IsString()
  to?: string;

  @IsOptional()
  @IsString()
  estado?: string;
}
