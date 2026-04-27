import { IsBase64, IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';

export class SendCotizacionWhatsappDto {
  @IsUUID()
  quotationId!: string;

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