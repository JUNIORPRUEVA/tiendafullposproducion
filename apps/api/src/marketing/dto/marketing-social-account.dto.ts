import { Transform } from 'class-transformer';
import { IsBoolean, IsEnum, IsOptional, IsString, MaxLength } from 'class-validator';
import { MarketingSocialAccountType } from '@prisma/client';

function normalizeOptionalString(value: unknown): string | undefined {
  if (value === null || value === undefined) return undefined;
  const text = String(value).trim();
  return text.length === 0 ? undefined : text;
}

function normalizeOptionalBool(value: unknown): boolean | undefined {
  if (value === null || value === undefined) return undefined;
  if (typeof value === 'boolean') return value;
  const text = String(value).trim().toLowerCase();
  if (text == 'true' || text == '1' || text == 'yes') return true;
  if (text == 'false' || text == '0' || text == 'no') return false;
  return undefined;
}

export class MarketingSocialAccountsQueryDto {
  @IsOptional()
  @IsEnum(MarketingSocialAccountType)
  type?: MarketingSocialAccountType;

  @IsOptional()
  @Transform(({ value }) => normalizeOptionalString(value))
  @IsString()
  search?: string;

  @IsOptional()
  @Transform(({ value }) => normalizeOptionalBool(value))
  @IsBoolean()
  activeOnly?: boolean;
}

export class CreateMarketingSocialAccountDto {
  @IsEnum(MarketingSocialAccountType)
  type!: MarketingSocialAccountType;

  @Transform(({ value }) => String(value ?? '').trim())
  @IsString()
  @MaxLength(160)
  accountName!: string;

  @IsOptional()
  @Transform(({ value }) => normalizeOptionalString(value))
  @IsString()
  @MaxLength(220)
  username?: string;

  @IsOptional()
  @Transform(({ value }) => normalizeOptionalString(value))
  @IsString()
  @MaxLength(320)
  password?: string;

  @IsOptional()
  @Transform(({ value }) => normalizeOptionalString(value))
  @IsString()
  @MaxLength(600)
  profileLink?: string;

  @IsOptional()
  @Transform(({ value }) => normalizeOptionalString(value))
  @IsString()
  @MaxLength(48)
  whatsappNumber?: string;

  @IsOptional()
  @Transform(({ value }) => normalizeOptionalString(value))
  @IsString()
  @MaxLength(2000)
  observations?: string;

  @IsOptional()
  @Transform(({ value }) => normalizeOptionalString(value))
  @IsString()
  @MaxLength(600)
  avatarUrl?: string;

  @IsOptional()
  @Transform(({ value }) => normalizeOptionalBool(value))
  @IsBoolean()
  isActive?: boolean;
}

export class UpdateMarketingSocialAccountDto {
  @IsOptional()
  @IsEnum(MarketingSocialAccountType)
  type?: MarketingSocialAccountType;

  @IsOptional()
  @Transform(({ value }) => normalizeOptionalString(value))
  @IsString()
  @MaxLength(160)
  accountName?: string;

  @IsOptional()
  @Transform(({ value }) => normalizeOptionalString(value))
  @IsString()
  @MaxLength(220)
  username?: string;

  @IsOptional()
  @Transform(({ value }) => normalizeOptionalString(value))
  @IsString()
  @MaxLength(320)
  password?: string;

  @IsOptional()
  @Transform(({ value }) => normalizeOptionalString(value))
  @IsString()
  @MaxLength(600)
  profileLink?: string;

  @IsOptional()
  @Transform(({ value }) => normalizeOptionalString(value))
  @IsString()
  @MaxLength(48)
  whatsappNumber?: string;

  @IsOptional()
  @Transform(({ value }) => normalizeOptionalString(value))
  @IsString()
  @MaxLength(2000)
  observations?: string;

  @IsOptional()
  @Transform(({ value }) => normalizeOptionalString(value))
  @IsString()
  @MaxLength(600)
  avatarUrl?: string;

  @IsOptional()
  @Transform(({ value }) => normalizeOptionalBool(value))
  @IsBoolean()
  isActive?: boolean;
}
