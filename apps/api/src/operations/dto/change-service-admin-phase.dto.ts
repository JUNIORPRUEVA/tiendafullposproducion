import { IsIn, IsOptional, IsString } from 'class-validator';

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

export class ChangeServiceAdminPhaseDto {
  @IsIn(adminPhases)
  adminPhase!: (typeof adminPhases)[number];

  @IsOptional()
  @IsString()
  message?: string;
}
