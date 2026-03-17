import { Transform, Type } from 'class-transformer';
import {
  IsArray,
  IsIn,
  IsInt,
  IsNotEmpty,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  Min,
} from 'class-validator';

const serviceTypes = ['installation', 'maintenance', 'warranty', 'pos_support', 'other'] as const;
const orderTypes = ['reserva', 'servicio', 'levantamiento', 'garantia', 'mantenimiento', 'instalacion'] as const;
const orderStates = ['pending', 'confirmed', 'assigned', 'in_progress', 'finalized', 'cancelled', 'rescheduled'] as const;

export class UpdateServiceDto {
  @IsOptional()
  @IsIn(serviceTypes)
  serviceType?: (typeof serviceTypes)[number];

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

  @IsOptional()
  @IsString()
  @IsNotEmpty()
  title?: string;

  @IsOptional()
  @IsString()
  @IsNotEmpty()
  description?: string;

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
  @IsString()
  addressSnapshot?: string;

  @IsOptional()
  @IsIn(orderTypes)
  orderType?: (typeof orderTypes)[number];

  @IsOptional()
  @IsIn(orderStates)
  orderState?: (typeof orderStates)[number];

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
