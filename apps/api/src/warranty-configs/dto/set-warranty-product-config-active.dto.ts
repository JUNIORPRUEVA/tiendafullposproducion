import { Type } from 'class-transformer';
import { IsBoolean } from 'class-validator';

export class SetWarrantyProductConfigActiveDto {
  @Type(() => Boolean)
  @IsBoolean()
  isActive!: boolean;
}