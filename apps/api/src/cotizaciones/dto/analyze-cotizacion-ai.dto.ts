import { Type } from 'class-transformer';
import { IsOptional, IsString, ValidateNested } from 'class-validator';
import { QuotationAiContextDto } from './quotation-ai-context.dto';

export class AnalyzeCotizacionAiDto {
  @ValidateNested()
  @Type(() => QuotationAiContextDto)
  context!: QuotationAiContextDto;

  @IsOptional()
  @IsString()
  instruction?: string;
}