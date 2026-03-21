import { IsIn, IsOptional, IsString } from 'class-validator';

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

export class ChangeServiceOrderStateDto {
  @IsIn(orderStates)
  orderState!: (typeof orderStates)[number];

  @IsOptional()
  @IsString()
  message?: string;
}
