import { IsDateString, IsIn, IsOptional, IsString } from 'class-validator';

export class GenerateWeekDto {
  @IsDateString()
  week_start_date!: string;

  @IsOptional()
  @IsIn(['REPLACE', 'KEEP_MANUAL'])
  mode?: 'REPLACE' | 'KEEP_MANUAL';

  @IsOptional()
  @IsString()
  note?: string;
}
