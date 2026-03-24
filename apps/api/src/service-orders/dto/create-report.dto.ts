import { IsIn, IsString } from 'class-validator';
import { SERVICE_REPORT_TYPE_VALUES } from '../service-orders.constants';

export class CreateReportDto {
  @IsString()
  @IsIn(SERVICE_REPORT_TYPE_VALUES)
  type!: string;

  @IsString()
  report!: string;
}