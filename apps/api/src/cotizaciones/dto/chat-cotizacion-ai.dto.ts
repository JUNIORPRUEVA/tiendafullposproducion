import { Type } from 'class-transformer';
import { IsString, ValidateNested } from 'class-validator';
import { QuotationAiContextDto } from './quotation-ai-context.dto';

export class ChatCotizacionAiDto {
  @ValidateNested()
  @Type(() => QuotationAiContextDto)
  context!: QuotationAiContextDto;

  @IsString()
  message!: string;
}