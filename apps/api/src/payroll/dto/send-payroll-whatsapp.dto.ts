import { IsBase64, IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';

export class SendPayrollWhatsappDto {
  @IsUUID()
  employeeId!: string;

  @IsUUID()
  periodId!: string;

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