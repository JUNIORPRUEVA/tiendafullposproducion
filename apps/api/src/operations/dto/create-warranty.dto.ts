import { IsOptional, IsString } from 'class-validator';

export class CreateWarrantyDto {
  @IsOptional()
  @IsString()
  title?: string;

  @IsOptional()
  @IsString()
  description?: string;
}