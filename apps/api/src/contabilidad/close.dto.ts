import {
  IsDateString,
  IsEnum,
  IsNumber,
  IsOptional,
  IsString,
  Min,
} from 'class-validator';

export enum CloseType {
  CAPSULAS = 'CAPSULAS',
  POS = 'POS',
  TIENDA = 'TIENDA',
  PHYTOEMAGRY = 'PHYTOEMAGRY',
}

export enum CloseStatus {
  PENDING = 'pending',
  APPROVED = 'approved',
  REJECTED = 'rejected',
}

export class CreateCloseDto {
  @IsEnum(CloseType)
  type!: CloseType;

  @IsDateString()
  date!: string;

  @IsNumber()
  @Min(0)
  cash!: number;

  @IsNumber()
  @Min(0)
  transfer!: number;

  @IsString()
  @IsOptional()
  transferBank?: string;

  @IsNumber()
  @Min(0)
  card!: number;

  @IsNumber()
  @Min(0)
  @IsOptional()
  otherIncome?: number;

  @IsNumber()
  @Min(0)
  expenses!: number;

  @IsNumber()
  @Min(0)
  cashDelivered!: number;

  @IsString()
  @IsOptional()
  notes?: string;

  @IsString()
  @IsOptional()
  evidenceUrl?: string;

  @IsString()
  @IsOptional()
  evidenceFileName?: string;
}

export class UpdateCloseDto {
  @IsNumber()
  @IsOptional()
  @Min(0)
  cash?: number;

  @IsNumber()
  @IsOptional()
  @Min(0)
  transfer?: number;

  @IsString()
  @IsOptional()
  transferBank?: string;

  @IsNumber()
  @IsOptional()
  @Min(0)
  card?: number;

  @IsNumber()
  @IsOptional()
  @Min(0)
  otherIncome?: number;

  @IsNumber()
  @IsOptional()
  @Min(0)
  expenses?: number;

  @IsNumber()
  @IsOptional()
  @Min(0)
  cashDelivered?: number;

  @IsString()
  @IsOptional()
  notes?: string;

  @IsString()
  @IsOptional()
  evidenceUrl?: string;

  @IsString()
  @IsOptional()
  evidenceFileName?: string;
}
