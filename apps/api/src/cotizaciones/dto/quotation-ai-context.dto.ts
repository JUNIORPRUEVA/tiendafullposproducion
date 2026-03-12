import { Type } from 'class-transformer';
import {
  IsArray,
  IsNumber,
  IsObject,
  IsOptional,
  IsString,
  ValidateNested,
} from 'class-validator';

export class QuotationAiContextItemDto {
  @IsOptional()
  @IsString()
  productId?: string;

  @IsOptional()
  @IsString()
  productName?: string;

  @IsOptional()
  @IsString()
  category?: string;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  qty?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  unitPrice?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  officialUnitPrice?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  lineTotal?: number;

  @IsOptional()
  @IsString()
  notes?: string;
}

export class QuotationAiContextDto {
  @IsOptional()
  @IsString()
  quotationId?: string;

  @IsOptional()
  @IsString()
  module?: string;

  @IsOptional()
  @IsString()
  productType?: string;

  @IsOptional()
  @IsString()
  productName?: string;

  @IsOptional()
  @IsString()
  brand?: string;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  quantity?: number;

  @IsOptional()
  @IsString()
  installationType?: string;

  @IsOptional()
  @IsString()
  selectedPriceType?: string;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  selectedUnitPrice?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  selectedTotal?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  minimumPrice?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  offerPrice?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  normalPrice?: number;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  components?: string[];

  @IsOptional()
  @IsString()
  notes?: string;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  extraCharges?: string[];

  @IsOptional()
  @IsString()
  currentDvrType?: string;

  @IsOptional()
  @IsString()
  requiredDvrType?: string;

  @IsOptional()
  @IsString()
  screenName?: string;

  @IsOptional()
  @IsObject()
  metadata?: Record<string, unknown>;

  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => QuotationAiContextItemDto)
  items?: QuotationAiContextItemDto[];
}