import { IsIn } from 'class-validator';
import { SERVICE_ORDER_STATUS_VALUES } from '../service-orders.constants';

export class UpdateStatusDto {
  @IsIn(SERVICE_ORDER_STATUS_VALUES)
  status!: string;
}