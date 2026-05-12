import { Transform, Type } from 'class-transformer';
import {
  IsArray,
  IsDateString,
  IsEnum,
  IsNumber,
  IsObject,
  IsOptional,
  IsString,
  MaxLength,
  Min,
} from 'class-validator';
import {
  MarketingCampaignCurrency,
  MarketingCampaignPhase,
  MarketingCampaignStatus,
} from '@prisma/client';

export class MarketingCampaignQueryDto {
  @IsOptional()
  @IsDateString()
  date?: string;
}

export class GenerateMarketingCampaignsDto {
  @IsOptional()
  @IsDateString()
  date?: string;
}

export class UploadCampaignDesignDto {
  @IsString()
  @MaxLength(2048)
  finalDesignUrl!: string;

  @IsOptional()
  @IsString()
  @MaxLength(255)
  fileName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  mimeType?: string;
}

export class UpdateMarketingCampaignDto {
  @IsOptional()
  @IsEnum(MarketingCampaignStatus)
  status?: MarketingCampaignStatus;

  @IsOptional()
  @IsEnum(MarketingCampaignPhase)
  phase?: MarketingCampaignPhase;

  @IsOptional()
  @IsString()
  @MaxLength(240)
  headline?: string;

  @IsOptional()
  @IsString()
  primaryText?: string;

  @IsOptional()
  @IsString()
  description?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  cta?: string;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  hashtags?: string[];

  @IsOptional()
  @IsString()
  aiAngle?: string;

  @IsOptional()
  @IsObject()
  recommendedAudienceJson?: Record<string, unknown>;

  @IsOptional()
  @IsObject()
  finalAudienceJson?: Record<string, unknown>;

  @IsOptional()
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  dailyBudget?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  totalBudget?: number;

  @IsOptional()
  @IsEnum(MarketingCampaignCurrency)
  currency?: MarketingCampaignCurrency;

  @IsOptional()
  @IsString()
  @MaxLength(50)
  whatsappPhone?: string;

  @IsOptional()
  @IsString()
  whatsappMessageTemplate?: string;

  @IsOptional()
  @IsString()
  @MaxLength(2048)
  destinationUrl?: string;

  @IsOptional()
  @IsDateString()
  startTime?: string;

  @IsOptional()
  @IsDateString()
  endTime?: string;

  @IsOptional()
  @Transform(({ value }) => value === true || value === 'true')
  keepRunningUntilPaused?: boolean;
}

export class CreateMetaCampaignDto {
  @IsOptional()
  @IsString()
  @MaxLength(120)
  objective?: string;

  @IsOptional()
  @Transform(({ value }) => value === true || value === 'true')
  activateAfterCreate?: boolean;
}

export class MetaActivationDto {
  @IsOptional()
  @Transform(({ value }) => value === true || value === 'true')
  adLevel?: boolean;
}
