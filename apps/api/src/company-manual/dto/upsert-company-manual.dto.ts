import { Type } from 'class-transformer';
import { CompanyManualAudience, CompanyManualEntryKind, Role } from '@prisma/client';
import { ArrayMaxSize, IsArray, IsBoolean, IsEnum, IsInt, IsOptional, IsString, IsUUID, MaxLength, Min } from 'class-validator';

export class UpsertCompanyManualDto {
  @IsOptional()
  @IsUUID()
  id?: string;

  @IsString()
  @MaxLength(180)
  title!: string;

  @IsOptional()
  @IsString()
  @MaxLength(300)
  summary?: string;

  @IsString()
  content!: string;

  @IsEnum(CompanyManualEntryKind)
  kind!: CompanyManualEntryKind;

  @IsEnum(CompanyManualAudience)
  audience!: CompanyManualAudience;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(5)
  @IsEnum(Role, { each: true })
  targetRoles?: Role[];

  @IsOptional()
  @IsString()
  @MaxLength(100)
  moduleKey?: string;

  @IsOptional()
  @Type(() => Boolean)
  @IsBoolean()
  published?: boolean;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  sortOrder?: number;
}