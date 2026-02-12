import { Role } from '@prisma/client';
import { IsEnum, IsOptional, IsUUID } from 'class-validator';
import { SalesQueryDto } from './sales-query.dto';

export class AdminSalesQueryDto extends SalesQueryDto {
  @IsOptional()
  @IsUUID()
  sellerId?: string;

  @IsOptional()
  @IsEnum(Role)
  role?: Role;
}
