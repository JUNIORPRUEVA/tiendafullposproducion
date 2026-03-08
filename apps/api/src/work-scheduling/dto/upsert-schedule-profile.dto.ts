import { IsArray, IsBoolean, IsInt, IsOptional, IsString, Max, Min, ValidateNested, IsEnum } from 'class-validator';
import { Type } from 'class-transformer';
import { WorkShiftKind } from '@prisma/client';

export class UpsertScheduleProfileDayDto {
  @IsInt()
  @Min(0)
  @Max(6)
  weekday!: number;

  @IsBoolean()
  is_working!: boolean;

  @IsEnum(WorkShiftKind)
  kind!: WorkShiftKind;

  @IsInt()
  @Min(0)
  @Max(24 * 60)
  start_minute!: number;

  @IsInt()
  @Min(0)
  @Max(24 * 60)
  end_minute!: number;
}

export class UpsertScheduleProfileDto {
  @IsOptional()
  @IsString()
  id?: string;

  @IsString()
  name!: string;

  @IsOptional()
  @IsBoolean()
  is_default?: boolean;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => UpsertScheduleProfileDayDto)
  days!: UpsertScheduleProfileDayDto[];
}
