import { IsOptional, IsUUID } from 'class-validator';

export class PayrollPaymentStatusQueryDto {
  @IsUUID()
  periodId!: string;

  @IsOptional()
  @IsUUID()
  employeeId?: string;
}

export class MarkPayrollPaidDto {
  @IsUUID()
  periodId!: string;

  @IsUUID()
  employeeId!: string;
}
