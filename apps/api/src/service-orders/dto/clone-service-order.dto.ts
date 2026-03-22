import { IsIn, IsOptional, IsString, IsUUID } from 'class-validator';
import { SERVICE_ORDER_TYPE_VALUES } from '../service-orders.constants';

export class CloneServiceOrderDto {
  @IsOptional()
  @IsIn(SERVICE_ORDER_TYPE_VALUES)
  serviceType?: string;

  @IsOptional()
  @IsIn(SERVICE_ORDER_TYPE_VALUES)
  service_type?: string;

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
}