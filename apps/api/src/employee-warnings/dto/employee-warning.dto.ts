import {
  IsDateString,
  IsEnum,
  IsBoolean,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
} from 'class-validator';
import {
  EmployeeWarningType,
} from '@prisma/client';

export class CreateEmployeeWarningDto {
  @IsUUID()
  employeeUserId!: string;

  @IsDateString()
  warningDate!: string;

  @IsDateString()
  incidentDate!: string;

  @IsString()
  @MaxLength(120)
  reason!: string;

  @IsEnum(EmployeeWarningType)
  warningType!: EmployeeWarningType;

  @IsString()
  details!: string;

  @IsOptional()
  @IsString()
  incidentTime?: string;

  @IsOptional()
  @IsString()
  incidentPlace?: string;

  @IsOptional()
  @IsUUID()
  issuedByUserId?: string;

  @IsOptional()
  @IsString()
  issuedByNameSnapshot?: string;

  @IsOptional()
  @IsString()
  issuedByPositionSnapshot?: string;

  @IsOptional()
  @IsString()
  internalNotes?: string;

  @IsOptional()
  @IsBoolean()
  saveAsDraft?: boolean;
}

export class UpdateEmployeeWarningDto {
  @IsOptional()
  @IsDateString()
  warningDate?: string;

  @IsOptional()
  @IsDateString()
  incidentDate?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  reason?: string;

  @IsOptional()
  @IsEnum(EmployeeWarningType)
  warningType?: EmployeeWarningType;

  @IsOptional()
  @IsString()
  details?: string;

  @IsOptional()
  @IsString()
  incidentTime?: string;

  @IsOptional()
  @IsString()
  incidentPlace?: string;

  @IsOptional()
  @IsString()
  issuedByNameSnapshot?: string;

  @IsOptional()
  @IsString()
  issuedByPositionSnapshot?: string;

  @IsOptional()
  @IsString()
  internalNotes?: string;

  @IsOptional()
  @IsBoolean()
  saveAsDraft?: boolean;
}

export class AnnulEmployeeWarningDto {
  @IsString()
  annulmentReason!: string;
}

export class SignEmployeeWarningDto {
  @IsString()
  typedName!: string;

  @IsOptional()
  @IsString()
  comment?: string;

  @IsOptional()
  @IsString()
  signatureImageUrl?: string;

  @IsOptional()
  @IsString()
  deviceInfo?: string;
}

export class RefuseEmployeeWarningDto {
  @IsString()
  typedName!: string;

  @IsString()
  comment!: string;

  @IsOptional()
  @IsString()
  deviceInfo?: string;
}

export class EmployeeWarningsQueryDto {
  @IsOptional()
  @IsString()
  employeeUserId?: string;

  @IsOptional()
  @IsString()
  status?: string;

  @IsOptional()
  @IsString()
  warningType?: string;

  @IsOptional()
  @IsString()
  search?: string;

  @IsOptional()
  @IsString()
  fromDate?: string;

  @IsOptional()
  @IsString()
  toDate?: string;

  @IsOptional()
  @IsString()
  page?: string;

  @IsOptional()
  @IsString()
  limit?: string;
}
