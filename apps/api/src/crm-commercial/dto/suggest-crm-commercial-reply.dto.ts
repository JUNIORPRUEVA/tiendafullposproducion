import { IsArray, IsObject, IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';

export class SuggestCrmCommercialReplyDto {
  @IsUUID()
  conversationId!: string;

  @IsOptional()
  @IsString()
  @MaxLength(4000)
  lastCustomerMessage?: string;

  @IsOptional()
  @IsArray()
  recentMessages?: Array<Record<string, unknown>>;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  crmStatus?: string;

  @IsOptional()
  @IsObject()
  customerInfo?: Record<string, unknown>;

  @IsOptional()
  @IsObject()
  availableBusinessData?: Record<string, unknown>;
}
