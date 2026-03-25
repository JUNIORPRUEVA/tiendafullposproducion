import { IsOptional, IsString } from 'class-validator';

export class ReviewServiceCommissionDto {
  @IsOptional()
  @IsString()
  note?: string;
}