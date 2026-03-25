import { IsDateString, IsOptional } from 'class-validator';

export class ServiceOrderSalesSummaryQueryDto {
  @IsOptional()
  @IsDateString()
  from?: string;

  @IsOptional()
  @IsDateString()
  to?: string;
}