import { IsDateString, IsOptional, IsString } from 'class-validator';

export class ScheduleServiceDto {
  @IsDateString()
  scheduledStart!: string;

  @IsDateString()
  scheduledEnd!: string;

  @IsOptional()
  @IsString()
  message?: string;
}