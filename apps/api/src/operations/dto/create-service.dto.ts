import { Transform, Type } from 'class-transformer';
import { IsArray, IsIn, IsInt, IsNotEmpty, IsNumber, IsOptional, IsString, IsUUID, Max, Min } from 'class-validator';

const serviceTypes = ['installation', 'maintenance', 'warranty', 'pos_support', 'other'] as const;

export class CreateServiceDto {
  @IsUUID()
  customerId!: string;

  @IsIn(serviceTypes)
  serviceType!: (typeof serviceTypes)[number];

  @IsString()
  @IsNotEmpty()
  category!: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(3)
  priority?: number;

  @IsString()
  @IsNotEmpty()
  title!: string;

  @IsString()
  @IsNotEmpty()
  description!: string;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  quotedAmount?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  depositAmount?: number;

  @IsOptional()
  @IsIn(['pending', 'partial', 'paid'])
  paymentStatus?: 'pending' | 'partial' | 'paid';

  @IsOptional()
  @IsString()
  addressSnapshot?: string;

  @IsOptional()
  @IsUUID()
  warrantyParentServiceId?: string;

  @IsOptional()
  @IsArray()
  @Transform(({ value }) => {
    if (Array.isArray(value)) return value;
    if (typeof value === 'string' && value.trim().length > 0) {
      return value
        .split(',')
        .map((s: string) => s.trim())
        .filter((s: string) => s.length > 0);
    }
    return [];
  })
  tags?: string[];
}
