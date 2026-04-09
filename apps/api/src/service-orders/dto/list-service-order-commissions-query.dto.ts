import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, Max, Min } from 'class-validator';

const SERVICE_ORDER_COMMISSION_PERIOD_VALUES = ['current', 'previous'] as const;

export class ListServiceOrderCommissionsQueryDto {
  @IsOptional()
  @IsIn(SERVICE_ORDER_COMMISSION_PERIOD_VALUES)
  period?: 'current' | 'previous';

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  pageSize?: number;
}