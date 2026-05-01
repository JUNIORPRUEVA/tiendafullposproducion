import {
  IsDateString,
  IsEnum,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
} from 'class-validator';
import {
  EmployeeWarningCategory,
  EmployeeWarningSeverity,
} from '@prisma/client';

export class CreateEmployeeWarningDto {
  @IsUUID()
  employeeUserId!: string;

  @IsDateString()
  warningDate!: string;

  @IsDateString()
  incidentDate!: string;

  @IsString()
  @MaxLength(200)
  title!: string;

  @IsEnum(EmployeeWarningCategory)
  category!: EmployeeWarningCategory;

  @IsEnum(EmployeeWarningSeverity)
  severity!: EmployeeWarningSeverity;

  @IsOptional()
  @IsString()
  legalBasis?: string;

  @IsOptional()
  @IsString()
  internalRuleReference?: string;

  @IsString()
  description!: string;

  @IsOptional()
  @IsString()
  employeeExplanation?: string;

  @IsOptional()
  @IsString()
  correctiveAction?: string;

  @IsOptional()
  @IsString()
  consequenceNote?: string;

  @IsOptional()
  @IsString()
  evidenceNotes?: string;
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
  @MaxLength(200)
  title?: string;

  @IsOptional()
  @IsEnum(EmployeeWarningCategory)
  category?: EmployeeWarningCategory;

  @IsOptional()
  @IsEnum(EmployeeWarningSeverity)
  severity?: EmployeeWarningSeverity;

  @IsOptional()
  @IsString()
  legalBasis?: string;

  @IsOptional()
  @IsString()
  internalRuleReference?: string;

  @IsOptional()
  @IsString()
  description?: string;

  @IsOptional()
  @IsString()
  employeeExplanation?: string;

  @IsOptional()
  @IsString()
  correctiveAction?: string;

  @IsOptional()
  @IsString()
  consequenceNote?: string;

  @IsOptional()
  @IsString()
  evidenceNotes?: string;
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
  severity?: string;

  @IsOptional()
  @IsString()
  category?: string;

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
