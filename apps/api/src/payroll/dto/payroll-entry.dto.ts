import { PayrollEntryType } from '@prisma/client';
import { Type } from 'class-transformer';
import { IsDateString, IsEnum, IsNumber, IsOptional, IsString, IsUUID } from 'class-validator';

export class PayrollEntriesQueryDto {
  @IsUUID()
  periodId!: string;

  @IsUUID()
  employeeId!: string;
}

export class AddPayrollEntryDto {
  @IsUUID()
  periodId!: string;

  @IsUUID()
  employeeId!: string;

  @IsDateString()
  date!: string;

  @IsEnum(PayrollEntryType)
  type!: PayrollEntryType;

  @IsString()
  concept!: string;

  @Type(() => Number)
  @IsNumber()
  amount!: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  cantidad?: number;
}
