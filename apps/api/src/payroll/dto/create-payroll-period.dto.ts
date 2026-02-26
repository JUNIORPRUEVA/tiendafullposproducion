import { IsDateString, IsString } from 'class-validator';

export class CreatePayrollPeriodDto {
  @IsDateString()
  start!: string;

  @IsDateString()
  end!: string;

  @IsString()
  title!: string;
}
