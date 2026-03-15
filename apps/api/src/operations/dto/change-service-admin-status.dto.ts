import { IsIn, IsOptional, IsString } from 'class-validator';

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

export class ChangeServiceAdminStatusDto {
  @IsIn(adminStatuses)
  adminStatus!: (typeof adminStatuses)[number];

  @IsOptional()
  @IsString()
  message?: string;
}
