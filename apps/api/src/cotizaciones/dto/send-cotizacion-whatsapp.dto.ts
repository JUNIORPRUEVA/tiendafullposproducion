import { IsBase64, IsOptional, IsString, MaxLength } from 'class-validator';

export class SendCotizacionWhatsappDto {
  @IsString()
  @MaxLength(80)
  customerName!: string;

  @IsString()
  @MaxLength(40)
  customerPhone!: string;

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