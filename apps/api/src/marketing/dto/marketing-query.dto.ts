import { Transform } from 'class-transformer';
import { IsDateString, IsIn, IsInt, IsOptional, IsString } from 'class-validator';

function toOptionalInt(value: unknown): number | undefined {
  if (value === null || value === undefined) return undefined;
  const raw = String(value).trim();
  if (!raw) return undefined;

  const parsed = Number(raw);
  if (!Number.isFinite(parsed)) return undefined;
  return Math.trunc(parsed);
}

export class MarketingQueryDto {
  @IsOptional()
  @IsDateString()
  date?: string;
}

export class MarketingHistoryQueryDto {
  @IsOptional()
  @IsDateString()
  from?: string;

  @IsOptional()
  @IsDateString()
  to?: string;

  @IsOptional()
  @IsIn(['SALES', 'TRUST', 'EDUCATIONAL'])
  type?: 'SALES' | 'TRUST' | 'EDUCATIONAL';

  @IsOptional()
  @IsIn(['PENDING', 'APPROVED', 'REJECTED', 'REGENERATED'])
  status?: 'PENDING' | 'APPROVED' | 'REJECTED' | 'REGENERATED';

  @IsOptional()
  @IsString()
  search?: string;

  @Transform(({ value }) => {
    const parsed = toOptionalInt(value);
    if (parsed === undefined) return 1;
    return Math.max(1, parsed);
  })
  @IsInt()
  page: number = 1;

  @Transform(({ value }) => {
    const parsed = toOptionalInt(value);
    if (parsed === undefined) return 20;
    return Math.min(100, Math.max(1, parsed));
  })
  @IsInt()
  limit: number = 20;
}
