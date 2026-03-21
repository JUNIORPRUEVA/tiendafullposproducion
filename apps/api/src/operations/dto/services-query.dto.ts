import { Transform, Type } from 'class-transformer';
import { IsDateString, IsIn, IsInt, IsOptional, IsString, IsUUID, Max, Min } from 'class-validator';

const serviceStatuses = ['reserved', 'survey', 'scheduled', 'in_progress', 'completed', 'warranty', 'closed', 'cancelled'] as const;
const serviceTypes = [
  'installation',
  'maintenance',
  'warranty',
  'pos_support',
  'other',
  'instalacion',
  'mantenimiento',
  'garantia',
  'levantamiento',
  'reserva',
  'survey',
] as const;
const orderTypes = ['reserva', 'servicio', 'levantamiento', 'garantia', 'mantenimiento', 'instalacion'] as const;
const orderStates = [
  'pending',
  'confirmed',
  'assigned',
  'in_progress',
  'finalized',
  'cancelled',
  'rescheduled',
  'pendiente',
  'confirmada',
  'asignada',
  'en_camino',
  'en_proceso',
  'finalizada',
  'cancelada',
  'reagendada',
  'cerrada',
] as const;
const adminPhases = [
  'reserva',
  'confirmacion',
  'programacion',
  'ejecucion',
  'revision',
  'facturacion',
  'cierre',
  'cancelada',
] as const;
const adminStatuses = [
  'pendiente',
  'confirmada',
  'asignada',
  'en_camino',
  'en_proceso',
  'finalizada',
  'reagendada',
  'cancelada',
  'cerrada',
] as const;

export class ServicesQueryDto {
  @IsOptional()
  @IsIn(serviceStatuses)
  status?: (typeof serviceStatuses)[number];

  @IsOptional()
  @IsIn(serviceTypes)
  type?: (typeof serviceTypes)[number];

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(3)
  priority?: number;

  @IsOptional()
  @IsUUID()
  assignedTo?: string;

  @IsOptional()
  @IsIn(orderTypes)
  orderType?: (typeof orderTypes)[number];

  @IsOptional()
  @IsIn(orderStates)
  orderState?: (typeof orderStates)[number];

  @IsOptional()
  @IsIn(adminPhases)
  adminPhase?: (typeof adminPhases)[number];

  @IsOptional()
  @IsIn(adminStatuses)
  adminStatus?: (typeof adminStatuses)[number];

  @IsOptional()
  @IsUUID()
  technicianId?: string;

  @IsOptional()
  @IsDateString()
  from?: string;

  @IsOptional()
  @IsDateString()
  to?: string;

  @IsOptional()
  @IsUUID()
  customerId?: string;

  @IsOptional()
  @IsString()
  search?: string;

  @IsOptional()
  @IsString()
  category?: string;

  @IsOptional()
  @IsUUID()
  sellerId?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(200)
  pageSize?: number;

  @IsOptional()
  @Transform(({ value }) => value === true || value === 'true')
  includeDeleted?: boolean;
}
