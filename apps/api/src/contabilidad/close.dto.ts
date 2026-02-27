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
}

export class CreateCloseDto {
  @IsEnum(CloseType)
  type!: CloseType;

  @IsDateString()
  @IsOptional()
  date?: string;

  @IsString()
  status!: string;

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
  expenses!: number;

  @IsNumber()
  @Min(0)
  cashDelivered!: number;
}

export class UpdateCloseDto {
  @IsString()
  @IsOptional()
  status?: string;

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
  expenses?: number;

  @IsNumber()
  @IsOptional()
  @Min(0)
  cashDelivered?: number;
}