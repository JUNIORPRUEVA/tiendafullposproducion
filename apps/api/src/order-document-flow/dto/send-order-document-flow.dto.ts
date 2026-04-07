import { IsBase64, IsOptional, IsString, MaxLength } from 'class-validator';

export class SendOrderDocumentFlowDto {
  @IsOptional()
  @IsBase64()
  invoicePdfBase64?: string;

  @IsOptional()
  @IsBase64()
  warrantyPdfBase64?: string;

  @IsOptional()
  @IsString()
  @MaxLength(180)
  invoiceFileName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(180)
  warrantyFileName?: string;
}