import { IsIn, IsOptional, IsString } from 'class-validator';

const orderStates = [
  'pending',
  'confirmed',
  'assigned',
  'in_progress',
  'finalized',
  'cancelled',
  'rescheduled',
] as const;

export class ChangeServiceOrderStateDto {
  @IsIn(orderStates)
  orderState!: (typeof orderStates)[number];

  @IsOptional()
  @IsString()
  message?: string;
}
