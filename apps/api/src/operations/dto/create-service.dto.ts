import { Transform, Type } from 'class-transformer';
import { IsArray, IsIn, IsInt, IsNotEmpty, IsNumber, IsOptional, IsString, IsUUID, Max, Min } from 'class-validator';

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

export class CreateServiceDto {
  @IsUUID()
  customerId!: string;

  @IsIn(serviceTypes)
  serviceType!: (typeof serviceTypes)[number];

  @IsOptional()
  @IsUUID()
  categoryId?: string;

  @IsOptional()
  @IsString()
  @IsNotEmpty()
  category?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(3)
  priority?: number;

  @IsString()
  @IsNotEmpty()
  title!: string;

  @IsString()
  @IsNotEmpty()
  description!: string;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  quotedAmount?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  depositAmount?: number;

  @IsOptional()
  @IsIn(['pending', 'partial', 'paid'])
  paymentStatus?: 'pending' | 'partial' | 'paid';

  @IsOptional()
  @IsString()
  addressSnapshot?: string;

  @IsOptional()
  @IsUUID()
  warrantyParentServiceId?: string;

  @IsOptional()
  @IsString()
  surveyResult?: string;

  @IsOptional()
  @IsString()
  materialsUsed?: string;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  finalCost?: number;

  @IsOptional()
  @IsIn(orderTypes)
  orderType?: (typeof orderTypes)[number];

  @IsOptional()
  @IsIn(orderStates)
  orderState?: (typeof orderStates)[number];

  // Admin-only conceptual model.
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
  @IsArray()
  @Transform(({ value }) => {
    if (Array.isArray(value)) return value;
    if (typeof value === 'string' && value.trim().length > 0) {
      return value
        .split(',')
        .map((s: string) => s.trim())
        .filter((s: string) => s.length > 0);
    }
    return [];
  })
  tags?: string[];
}
