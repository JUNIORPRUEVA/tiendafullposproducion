import { Transform } from 'class-transformer';
import { IsBoolean, IsDateString, IsOptional } from 'class-validator';

function toOptionalBool(value: unknown): boolean | undefined {
  if (value === undefined || value === null || value === '') return undefined;
  if (typeof value === 'boolean') return value;
  const raw = String(value).trim().toLowerCase();
  if (['true', '1', 'yes', 'si'].includes(raw)) return true;
  if (['false', '0', 'no'].includes(raw)) return false;
  return undefined;
}

export class MarketingResetCleanDto {
  @Transform(({ value }) => toOptionalBool(value))
  @IsOptional()
  @IsBoolean()
  includeResearch?: boolean;

  @Transform(({ value }) => toOptionalBool(value))
  @IsOptional()
  @IsBoolean()
  includeDraftMedia?: boolean;

  @Transform(({ value }) => toOptionalBool(value))
  @IsOptional()
  @IsBoolean()
  includeMediaAssets?: boolean;

  @Transform(({ value }) => toOptionalBool(value))
  @IsOptional()
  @IsBoolean()
  includeGeneratedImages?: boolean;

  @Transform(({ value }) => toOptionalBool(value))
  @IsOptional()
  @IsBoolean()
  includeApprovedStories?: boolean;

  @IsOptional()
  @IsDateString()
  date?: string;
}
