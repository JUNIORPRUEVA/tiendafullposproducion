import { IsArray, IsBoolean, IsInt, IsOptional, IsString, Max, Min } from 'class-validator';

export class UpdateEmployeeConfigDto {
  @IsOptional()
  @IsBoolean()
  enabled?: boolean;

  @IsOptional()
  @IsString()
  schedule_profile_id?: string | null;

  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(6)
  preferred_day_off_weekday?: number | null;

  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(6)
  fixed_day_off_weekday?: number | null;

  @IsOptional()
  @IsArray()
  @IsInt({ each: true })
  @Min(0, { each: true })
  @Max(6, { each: true })
  disallowed_day_off_weekdays?: number[];

  @IsOptional()
  @IsArray()
  @IsInt({ each: true })
  @Min(0, { each: true })
  @Max(6, { each: true })
  unavailable_weekdays?: number[];

  @IsOptional()
  @IsString()
  notes?: string | null;
}
