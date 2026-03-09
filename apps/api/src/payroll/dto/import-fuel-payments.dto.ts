import { IsOptional, IsUUID } from 'class-validator';

export class ImportFuelPaymentsDto {
  @IsUUID()
  periodId!: string;

  @IsOptional()
  @IsUUID()
  employeeId?: string;
}