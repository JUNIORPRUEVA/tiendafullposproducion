import { Type } from 'class-transformer';
import { IsBoolean, IsNumber, IsOptional, IsString, IsUUID, Min } from 'class-validator';

export class UpsertPayrollConfigDto {
  @IsUUID()
  periodId!: string;

  @IsUUID()
  employeeId!: string;

  @Type(() => Number)
  @IsNumber()
  @Min(0)
  baseSalary!: number;

  @Type(() => Boolean)
  @IsBoolean()
  includeCommissions!: boolean;

  @IsOptional()
  @IsString()
  notes?: string;
}
