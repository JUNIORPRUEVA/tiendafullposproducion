import { IsBase64, IsIn, IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';

export class SendCotizacionWhatsappDto {
  @IsUUID()
  quotationId!: string;

  @IsString()
  @IsIn(['admin', 'client'])
  destinationType!: 'admin' | 'client';

  @IsBase64()
  pdfBase64!: string;

  @IsOptional()
  @IsString()
  @MaxLength(180)
  fileName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(1500)
  messageText?: string;
}