import { Transform, Type } from 'class-transformer';
import { IsDateString, IsIn, IsInt, IsOptional, IsString, IsUUID, Max, Min } from 'class-validator';

const serviceStatuses = ['reserved', 'survey', 'scheduled', 'in_progress', 'completed', 'warranty', 'closed', 'cancelled'] as const;
const serviceTypes = ['installation', 'maintenance', 'warranty', 'pos_support', 'other'] as const;

export class ServicesQueryDto {
  @IsOptional()
  @IsIn(serviceStatuses)
  status?: (typeof serviceStatuses)[number];

  @IsOptional()
  @IsIn(serviceTypes)
  type?: (typeof serviceTypes)[number];

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(3)
  priority?: number;

  @IsOptional()
  @IsUUID()
  assignedTo?: string;

  @IsOptional()
  @IsDateString()
  from?: string;

  @IsOptional()
  @IsDateString()
  to?: string;

  @IsOptional()
  @IsUUID()
  customerId?: string;

  @IsOptional()
  @IsString()
  search?: string;

  @IsOptional()
  @IsString()
  category?: string;

  @IsOptional()
  @IsUUID()
  sellerId?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(200)
  pageSize?: number;

  @IsOptional()
  @Transform(({ value }) => value === true || value === 'true')
  includeDeleted?: boolean;
}