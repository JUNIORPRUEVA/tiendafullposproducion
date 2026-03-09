import { Type } from 'class-transformer';
import {
  IsArray,
  IsDateString,
  IsObject,
  IsOptional,
  IsString,
  MinLength,
  ValidateNested,
} from 'class-validator';

export class WorkContractClauseInputDto {
  @IsString()
  key!: string;

  @IsOptional()
  @IsString()
  label?: string;

  @IsString()
  title!: string;

  @IsString()
  text!: string;
}

export class WorkContractCurrentFieldsDto {
  @IsOptional()
  @IsString()
  workContractJobTitle?: string;

  @IsOptional()
  @IsString()
  workContractSalary?: string;

  @IsOptional()
  @IsString()
  workContractPaymentFrequency?: string;

  @IsOptional()
  @IsString()
  workContractPaymentMethod?: string;

  @IsOptional()
  @IsString()
  workContractWorkSchedule?: string;

  @IsOptional()
  @IsString()
  workContractWorkLocation?: string;

  @IsOptional()
  @IsObject()
  workContractClauseOverrides?: Record<string, string>;

  @IsOptional()
  @IsString()
  workContractCustomClauses?: string;

  @IsOptional()
  @IsDateString()
  workContractStartDate?: string;
}

export class AiEditWorkContractDto {
  @IsString()
  @MinLength(10)
  instruction!: string;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => WorkContractClauseInputDto)
  currentClauses!: WorkContractClauseInputDto[];

  @IsOptional()
  @ValidateNested()
  @Type(() => WorkContractCurrentFieldsDto)
  currentFields?: WorkContractCurrentFieldsDto;
}