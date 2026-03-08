import { IsDateString, IsOptional, IsString, IsUUID } from 'class-validator';

export class ManualMoveDayOffDto {
  @IsDateString()
  week_start_date!: string;

  @IsUUID()
  user_id!: string;

  @IsDateString()
  from_date!: string;

  @IsDateString()
  to_date!: string;

  @IsOptional()
  @IsString()
  reason?: string;
}

export class ManualSwapDayOffDto {
  @IsDateString()
  week_start_date!: string;

  @IsUUID()
  user_a_id!: string;

  @IsDateString()
  user_a_day_off_date!: string;

  @IsUUID()
  user_b_id!: string;

  @IsDateString()
  user_b_day_off_date!: string;

  @IsOptional()
  @IsString()
  reason?: string;
}
