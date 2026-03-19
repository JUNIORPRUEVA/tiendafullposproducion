import { Transform, Type } from 'class-transformer';
import { IsArray, IsBoolean, IsOptional, IsString, IsUUID } from 'class-validator';

function splitProducts(raw: unknown) {
  if (Array.isArray(raw)) {
    return raw
      .map((item) => (item ?? '').toString().trim())
      .filter((item) => item.length > 0);
  }
  const text = (raw ?? '').toString().trim();
  if (!text) return [];
  return text
    .split(',')
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
}

export class WarrantyProductConfigQueryDto {
  @IsOptional()
  @IsUUID()
  categoryId?: string;

  @IsOptional()
  @IsString()
  categoryCode?: string;

  @IsOptional()
  @IsString()
  search?: string;

  @IsOptional()
  @Transform(({ value }) => splitProducts(value))
  @IsArray()
  @IsString({ each: true })
  products?: string[];

  @IsOptional()
  @Type(() => Boolean)
  @IsBoolean()
  includeInactive?: boolean;
}