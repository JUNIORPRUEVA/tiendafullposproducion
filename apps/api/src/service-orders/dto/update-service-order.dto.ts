import { IsDateString, IsIn, IsOptional, IsString, IsUUID } from 'class-validator';
import {
  SERVICE_ORDER_CATEGORY_VALUES,
  SERVICE_ORDER_TYPE_VALUES,
} from '../service-orders.constants';

export class UpdateServiceOrderDto {
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
  @IsString()
  technicalNote?: string | null;

  @IsOptional()
  @IsString()
  technical_note?: string | null;

  @IsOptional()
  @IsString()
  extraRequirements?: string | null;

  @IsOptional()
  @IsString()
  extra_requirements?: string | null;

  @IsOptional()
  @IsUUID()
  assignedToId?: string | null;

  @IsOptional()
  @IsUUID()
  assigned_to?: string | null;

  @IsOptional()
  @IsDateString()
  scheduledFor?: string | null;

  @IsOptional()
  @IsDateString()
  scheduled_for?: string | null;

  @IsOptional()
  @IsDateString()
  scheduledAt?: string | null;

  @IsOptional()
  @IsDateString()
  scheduled_at?: string | null;
}
