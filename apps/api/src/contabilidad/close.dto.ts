import { IsEnum, IsString, IsNumber, IsDateString, IsOptional } from 'class-validator';

export enum CloseType {
  CAPSULAS = 'CAPSULAS',
  POS = 'POS',
  TIENDA = 'TIENDA',
}

export class CreateCloseDto {
  @IsEnum(CloseType)
  type: CloseType;

  @IsDateString()
  @IsOptional()
  date?: string;

  @IsString()
  status: string;

  @IsNumber()
  cash: number;

  @IsNumber()
  transfer: number;

  @IsNumber()
  card: number;

  @IsNumber()
  expenses: number;

  @IsNumber()
  cashDelivered: number;
}

export class UpdateCloseDto {
  @IsString()
  @IsOptional()
  status?: string;

  @IsNumber()
  @IsOptional()
  cash?: number;

  @IsNumber()
  @IsOptional()
  transfer?: number;

  @IsNumber()
  @IsOptional()
  card?: number;

  @IsNumber()
  @IsOptional()
  expenses?: number;

  @IsNumber()
  @IsOptional()
  cashDelivered?: number;
}