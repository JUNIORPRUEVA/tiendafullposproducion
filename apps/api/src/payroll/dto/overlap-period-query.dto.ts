import { IsDateString } from 'class-validator';

export class OverlapPeriodQueryDto {
  @IsDateString()
  start!: string;

  @IsDateString()
  end!: string;
}
