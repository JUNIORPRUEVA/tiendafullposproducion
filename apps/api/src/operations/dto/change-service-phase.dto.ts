import { IsDateString, IsIn, IsNotEmpty, IsOptional, IsString } from 'class-validator';

// NOTE: "reserva" is the default initial phase and is not allowed as a manual change.
const servicePhases = ['levantamiento', 'instalacion', 'mantenimiento', 'garantia'] as const;
const servicePhasesUpper = ['LEVANTAMIENTO', 'INSTALACION', 'MANTENIMIENTO', 'GARANTIA'] as const;

export class ChangeServicePhaseDto {
  // Accept both lowercase (Flutter) and uppercase (enum-style) inputs.
  @IsIn([...servicePhases, ...servicePhasesUpper])
  phase!: (typeof servicePhases)[number] | (typeof servicePhasesUpper)[number];

  // Required: always reschedule when changing phase.
  @IsDateString()
  @IsNotEmpty()
  scheduledAt!: string;

  @IsOptional()
  @IsString()
  note?: string;
}
