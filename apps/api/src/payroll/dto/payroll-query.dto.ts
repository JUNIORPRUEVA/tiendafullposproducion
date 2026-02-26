import { IsOptional, IsString, IsUUID } from 'class-validator';

export class PayrollTotalsQueryDto {
  @IsUUID()
  periodId!: string;

  @IsUUID()
  employeeId!: string;
}

export class PayrollGoalQueryDto {
  @IsOptional()
  @IsUUID()
  userId?: string;

  @IsOptional()
  @IsString()
  userName?: string;
}
