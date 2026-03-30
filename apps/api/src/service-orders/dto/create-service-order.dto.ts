import { IsDateString, IsIn, IsOptional, IsString, IsUUID } from 'class-validator';
import {
  SERVICE_ORDER_CATEGORY_VALUES,
  SERVICE_ORDER_STATUS_VALUES,
  SERVICE_ORDER_TYPE_VALUES,
} from '../service-orders.constants';

export class CreateServiceOrderDto {
  @IsOptional()
  @IsUUID()
  clientId?: string;

  @IsOptional()
  @IsUUID()
  client_id?: string;

  @IsOptional()
  @IsUUID()
  quotationId?: string;

  @IsOptional()
  @IsUUID()
  quotation_id?: string;

  @IsOptional()
  @IsIn(SERVICE_ORDER_CATEGORY_VALUES)
  category?: string;

  @IsOptional()
  @IsIn(SERVICE_ORDER_TYPE_VALUES)
  serviceType?: string;

  @IsOptional()
  @IsIn(SERVICE_ORDER_TYPE_VALUES)
  service_type?: string;

  @IsOptional()
  @IsIn(SERVICE_ORDER_STATUS_VALUES)
  status?: string;

  @IsOptional()
  @IsString()
  technicalNote?: string;

  @IsOptional()
  @IsString()
  technical_note?: string;

  @IsOptional()
  @IsString()
  extraRequirements?: string;

  @IsOptional()
  @IsString()
  extra_requirements?: string;

  @IsOptional()
  @IsUUID()
  assignedToId?: string;

  @IsOptional()
  @IsUUID()
  assigned_to?: string;

  @IsOptional()
  @IsDateString()
  scheduledFor?: string | null;

  @IsOptional()
  @IsDateString()
  scheduled_for?: string | null;
}