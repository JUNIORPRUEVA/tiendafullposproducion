import { Type } from 'class-transformer';
import {
  IsArray,
  IsDateString,
  IsNotEmpty,
  IsOptional,
  IsString,
  IsUUID,
  ValidateNested,
} from 'class-validator';
import { EstimatedProductItemDto } from './estimated-product-item.dto';

export class CreateTechnicalVisitDto {
  @IsUUID()
  order_id!: string;

  @IsUUID()
  technician_id!: string;

  @IsString()
  @IsNotEmpty()
  report_description!: string;

  @IsString()
  @IsNotEmpty()
  installation_notes!: string;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => EstimatedProductItemDto)
  estimated_products!: EstimatedProductItemDto[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  photos?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  videos?: string[];

  @IsOptional()
  @IsDateString()
  visit_date?: string;
}
