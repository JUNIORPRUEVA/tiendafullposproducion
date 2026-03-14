import {
  IsBoolean,
  IsNumber,
  IsOptional,
  IsString,
  MaxLength,
} from 'class-validator';

export class CreateExecutionChangeDto {
  @IsString()
  @MaxLength(80)
  type!: string;

  @IsString()
  @MaxLength(2000)
  description!: string;

  @IsOptional()
  @IsNumber()
  quantity?: number;

  @IsOptional()
  @IsNumber()
  extraCost?: number;

  @IsOptional()
  @IsBoolean()
  clientApproved?: boolean;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  note?: string;
}
