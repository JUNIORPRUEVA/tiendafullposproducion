import { Transform } from 'class-transformer';
import { IsBoolean, IsIn, IsObject, IsOptional, IsString, IsUUID } from 'class-validator';

const updateTypes = ['status_change', 'note', 'schedule_change', 'assignment_change', 'payment_update', 'step_update'] as const;

export class ServiceUpdateDto {
  @IsIn(updateTypes)
  type!: (typeof updateTypes)[number];

  @IsOptional()
  @IsObject()
  oldValue?: Record<string, unknown>;

  @IsOptional()
  @IsObject()
  newValue?: Record<string, unknown>;

  @IsOptional()
  @IsString()
  message?: string;

  @IsOptional()
  @IsUUID()
  stepId?: string;

  @IsOptional()
  @Transform(({ value }) => value === true || value === 'true')
  @IsBoolean()
  stepDone?: boolean;
}
