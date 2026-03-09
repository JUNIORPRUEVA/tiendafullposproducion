import { Type } from 'class-transformer';
import { IsISO8601, IsOptional } from 'class-validator';

export class CompanyManualSummaryDto {
  @IsOptional()
  @Type(() => String)
  @IsISO8601()
  seenAt?: string;
}