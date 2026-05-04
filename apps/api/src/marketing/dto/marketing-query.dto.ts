import { IsDateString, IsIn, IsInt, IsOptional, IsString, Max, Min } from 'class-validator';

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

  @IsOptional()
  @IsInt()
  @Min(1)
  page?: number;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number;
}
