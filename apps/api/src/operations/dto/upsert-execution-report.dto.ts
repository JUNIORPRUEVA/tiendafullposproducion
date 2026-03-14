import {
  IsBoolean,
  IsDateString,
  IsOptional,
  IsString,
  MaxLength,
} from 'class-validator';

export class UpsertExecutionReportDto {
  // Admin-like users may set this; technicians always write to their own id.
  @IsOptional()
  @IsString()
  technicianId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  phase?: string;

  @IsOptional()
  @IsDateString()
  arrivedAt?: string;

  @IsOptional()
  @IsDateString()
  startedAt?: string;

  @IsOptional()
  @IsDateString()
  finishedAt?: string;

  @IsOptional()
  @IsString()
  notes?: string;

  // JSON payloads: stored as jsonb. Keep validation permissive.
  @IsOptional()
  checklistData?: unknown;

  @IsOptional()
  phaseSpecificData?: unknown;

  @IsOptional()
  @IsBoolean()
  clientApproved?: boolean;
}
