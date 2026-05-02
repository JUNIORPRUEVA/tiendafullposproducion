import { IsDateString, IsIn, IsOptional, IsString, IsUUID } from 'class-validator';

export class MyPayrollHistoryQueryDto {
  @IsOptional()
  @IsDateString()
  from?: string;

  @IsOptional()
  @IsDateString()
  to?: string;

  @IsOptional()
  @IsIn(['DRAFT', 'PAID'])
  status?: string;

  @IsOptional()
  @IsUUID()
  periodId?: string;

  @IsOptional()
  @IsString()
  period?: string;
}
