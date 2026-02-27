import {
  IsDateString,
  IsEnum,
  IsNumber,
  IsObject,
  IsOptional,
  IsString,
  Min,
} from 'class-validator';

export enum DepositOrderStatusDto {
  PENDING = 'PENDING',
  EXECUTED = 'EXECUTED',
  CANCELLED = 'CANCELLED',
}

export class CreateDepositOrderDto {
  @IsDateString()
  windowFrom!: string;

  @IsDateString()
  windowTo!: string;

  @IsString()
  bankName!: string;

  @IsNumber()
  @Min(0)
  reserveAmount!: number;

  @IsNumber()
  @Min(0)
  totalAvailableCash!: number;

  @IsNumber()
  @Min(0)
  depositTotal!: number;

  @IsObject()
  closesCountByType!: Record<string, number>;

  @IsObject()
  depositByType!: Record<string, number>;

  @IsObject()
  accountByType!: Record<string, string>;
}

export class DepositOrdersQueryDto {
  @IsDateString()
  @IsOptional()
  from?: string;

  @IsDateString()
  @IsOptional()
  to?: string;

  @IsEnum(DepositOrderStatusDto)
  @IsOptional()
  status?: DepositOrderStatusDto;
}
