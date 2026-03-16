import { Type } from 'class-transformer';
import { IsArray, IsOptional, IsString, ValidateNested } from 'class-validator';
import { EstimatedProductItemDto } from './estimated-product-item.dto';

export class UpdateTechnicalVisitDto {
  @IsOptional()
  @IsString()
  report_description?: string;

  @IsOptional()
  @IsString()
  installation_notes?: string;

  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => EstimatedProductItemDto)
  estimated_products?: EstimatedProductItemDto[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  photos?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  videos?: string[];
}
