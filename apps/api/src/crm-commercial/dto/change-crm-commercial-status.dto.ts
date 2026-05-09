import { CrmCommercialCustomerStatus } from '@prisma/client';
import { IsEnum, IsOptional, IsString } from 'class-validator';

export class ChangeCrmCommercialStatusDto {
  @IsEnum(CrmCommercialCustomerStatus)
  status!: CrmCommercialCustomerStatus;

  @IsOptional()
  @IsString()
  note?: string;
}
