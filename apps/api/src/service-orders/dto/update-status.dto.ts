import { IsDateString, IsIn, IsOptional, IsString, MaxLength } from 'class-validator';
import { SERVICE_ORDER_STATUS_VALUES } from '../service-orders.constants';

export class UpdateStatusDto {
  @IsIn(SERVICE_ORDER_STATUS_VALUES)
  status!: string;

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

  @IsOptional()
  @IsString()
  @MaxLength(400)
  note?: string | null;
}