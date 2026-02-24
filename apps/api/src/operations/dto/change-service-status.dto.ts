import { Transform } from 'class-transformer';
import { IsBoolean, IsIn, IsOptional, IsString } from 'class-validator';

const serviceStatuses = ['reserved', 'survey', 'scheduled', 'in_progress', 'completed', 'warranty', 'closed', 'cancelled'] as const;

export class ChangeServiceStatusDto {
  @IsIn(serviceStatuses)
  status!: (typeof serviceStatuses)[number];

  @IsOptional()
  @Transform(({ value }) => value === true || value === 'true')
  @IsBoolean()
  force?: boolean;

  @IsOptional()
  @IsString()
  message?: string;
}