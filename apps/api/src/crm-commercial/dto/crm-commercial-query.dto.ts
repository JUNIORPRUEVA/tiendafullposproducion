import { Transform } from 'class-transformer';
import { CrmCommercialCustomerStatus } from '@prisma/client';
import { IsBooleanString, IsEnum, IsInt, IsOptional, IsString, IsUUID, Max, Min } from 'class-validator';

export class CrmCommercialQueryDto {
  @IsOptional()
  @IsString()
  q?: string;

  @IsOptional()
  @IsEnum(CrmCommercialCustomerStatus)
  status?: CrmCommercialCustomerStatus;

  @IsOptional()
  @IsUUID()
  responsableUserId?: string;

  @IsOptional()
  @IsBooleanString()
  onlyMine?: string;

  @IsOptional()
  @Transform(({ value }) => {
    if (value == null || value == '') return undefined;
    const num = Number(value);
    if (!Number.isFinite(num)) return undefined;
    return Math.max(1, Math.trunc(num));
  })
  @IsInt()
  @Min(1)
  page?: number;

  @IsOptional()
  @Transform(({ value }) => {
    if (value == null || value == '') return undefined;
    const num = Number(value);
    if (!Number.isFinite(num)) return undefined;
    return Math.max(1, Math.trunc(num));
  })
  @IsInt()
  @Min(1)
  @Max(200)
  pageSize?: number;
}
