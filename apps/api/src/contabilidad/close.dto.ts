import {
  IsArray,
  IsDateString,
  IsEnum,
  IsNumber,
  IsOptional,
  IsString,
  ValidateNested,
  Min,
} from 'class-validator';
import { Type } from 'class-transformer';

export class CloseExpenseDetailDto {
  @IsString()
  concept!: string;

  @IsNumber()
  @Min(0)
  amount!: number;
}

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

export class CloseTransferVoucherDto {
  @IsString()
  storageKey!: string;

  @IsString()
  fileUrl!: string;

  @IsString()
  fileName!: string;

  @IsString()
  mimeType!: string;
}

export class CloseTransferEntryDto {
  @IsString()
  bankName!: string;

  @IsNumber()
  @Min(0)
  amount!: number;

  @IsString()
  @IsOptional()
  referenceNumber?: string;

  @IsString()
  @IsOptional()
  note?: string;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => CloseTransferVoucherDto)
  vouchers!: CloseTransferVoucherDto[];
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

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => CloseTransferEntryDto)
  @IsOptional()
  transfers?: CloseTransferEntryDto[];

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

  @IsString()
  @IsOptional()
  evidenceStorageKey?: string;

  @IsString()
  @IsOptional()
  evidenceMimeType?: string;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => CloseExpenseDetailDto)
  @IsOptional()
  expenseDetails?: CloseExpenseDetailDto[];
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

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => CloseTransferEntryDto)
  @IsOptional()
  transfers?: CloseTransferEntryDto[];

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

  @IsString()
  @IsOptional()
  evidenceStorageKey?: string;

  @IsString()
  @IsOptional()
  evidenceMimeType?: string;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => CloseExpenseDetailDto)
  @IsOptional()
  expenseDetails?: CloseExpenseDetailDto[];
}

export class ReviewCloseDto {
  @IsString()
  @IsOptional()
  reviewNote?: string;
}
