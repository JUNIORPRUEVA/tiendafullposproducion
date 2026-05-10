import {
  IsArray,
  IsBoolean,
  IsEnum,
  IsInt,
  IsNotEmpty,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
} from 'class-validator';
import { Type } from 'class-transformer';
import { CrmCommercialLibraryItemType } from '@prisma/client';

export class CrmCommercialLibraryItemQueryDto {
  @IsOptional()
  @IsEnum(CrmCommercialLibraryItemType)
  type?: CrmCommercialLibraryItemType;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  category?: string;

  @IsOptional()
  @IsString()
  @MaxLength(240)
  search?: string;

  @IsOptional()
  @IsBoolean()
  @Type(() => Boolean)
  isActive?: boolean;

  @IsOptional()
  @IsInt()
  @Type(() => Number)
  limit?: number;
}

export class CreateCrmCommercialLibraryItemDto {
  @IsOptional()
  @IsUUID()
  companyId?: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(160)
  title!: string;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  description?: string;

  @IsEnum(CrmCommercialLibraryItemType)
  type!: CrmCommercialLibraryItemType;

  @IsOptional()
  @IsString()
  @MaxLength(4000)
  contentText?: string;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  mediaUrl?: string;

  @IsOptional()
  @IsString()
  @MaxLength(240)
  fileName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  mimeType?: string;

  @IsOptional()
  @IsNumber()
  @Type(() => Number)
  latitude?: number;

  @IsOptional()
  @IsNumber()
  @Type(() => Number)
  longitude?: number;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  externalUrl?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  category?: string;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  tags?: string[];

  @IsOptional()
  @IsBoolean()
  @Type(() => Boolean)
  isActive?: boolean;

  @IsOptional()
  @IsInt()
  @Type(() => Number)
  sortOrder?: number;
}

export class UpdateCrmCommercialLibraryItemDto {
  @IsOptional()
  @IsUUID()
  companyId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(160)
  title?: string;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  description?: string;

  @IsOptional()
  @IsEnum(CrmCommercialLibraryItemType)
  type?: CrmCommercialLibraryItemType;

  @IsOptional()
  @IsString()
  @MaxLength(4000)
  contentText?: string;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  mediaUrl?: string;

  @IsOptional()
  @IsString()
  @MaxLength(240)
  fileName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  mimeType?: string;

  @IsOptional()
  @IsNumber()
  @Type(() => Number)
  latitude?: number;

  @IsOptional()
  @IsNumber()
  @Type(() => Number)
  longitude?: number;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  externalUrl?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  category?: string;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  tags?: string[];

  @IsOptional()
  @IsBoolean()
  @Type(() => Boolean)
  isActive?: boolean;

  @IsOptional()
  @IsInt()
  @Type(() => Number)
  sortOrder?: number;
}
