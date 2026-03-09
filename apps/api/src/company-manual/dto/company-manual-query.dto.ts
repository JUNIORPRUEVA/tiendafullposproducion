import { Type } from 'class-transformer';
import { CompanyManualAudience, CompanyManualEntryKind, Role } from '@prisma/client';
import { IsBoolean, IsEnum, IsOptional, IsString } from 'class-validator';

export class CompanyManualQueryDto {
  @IsOptional()
  @IsEnum(CompanyManualEntryKind)
  kind?: CompanyManualEntryKind;

  @IsOptional()
  @IsEnum(CompanyManualAudience)
  audience?: CompanyManualAudience;

  @IsOptional()
  @IsEnum(Role)
  role?: Role;

  @IsOptional()
  @IsString()
  moduleKey?: string;

  @IsOptional()
  @Type(() => Boolean)
  @IsBoolean()
  includeHidden?: boolean;
}