import { Type } from 'class-transformer';
import { WarrantyDurationUnit } from '@prisma/client';
import {
  IsBoolean,
  IsEnum,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  Min,
  ValidateIf,
} from 'class-validator';

export class UpsertWarrantyProductConfigDto {
  @IsOptional()
  @IsUUID()
  categoryId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  categoryCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(140)
  categoryName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(180)
  productName?: string;

  @IsOptional()
  @Type(() => Boolean)
  @IsBoolean()
  hasWarranty?: boolean;

  @ValidateIf((dto) => dto.durationValue !== undefined && dto.durationValue !== null)
  @Type(() => Number)
  @IsInt()
  @Min(0)
  durationValue?: number;

  @IsOptional()
  @IsEnum(WarrantyDurationUnit)
  durationUnit?: WarrantyDurationUnit;

  @IsOptional()
  @IsString()
  @MaxLength(280)
  warrantySummary?: string;

  @IsOptional()
  @IsString()
  @MaxLength(600)
  coverageSummary?: string;

  @IsOptional()
  @IsString()
  @MaxLength(600)
  exclusionsSummary?: string;

  @IsOptional()
  @IsString()
  @MaxLength(400)
  notes?: string;

  @IsOptional()
  @Type(() => Boolean)
  @IsBoolean()
  isActive?: boolean;
}