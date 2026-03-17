import { IsDateString, IsOptional, IsString, MaxLength } from 'class-validator';

export class CreateServiceSignatureDto {
  @IsOptional()
  @IsString()
  signatureBase64?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  mimeType?: string;

  @IsOptional()
  @IsString()
  @MaxLength(180)
  fileName?: string;

  @IsOptional()
  @IsDateString()
  signedAt?: string;
}