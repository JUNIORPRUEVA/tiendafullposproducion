import { IsDateString, IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';

export class CreateCrmCommercialActivityDto {
  @IsString()
  @MaxLength(80)
  type!: string;

  @IsString()
  @MaxLength(5000)
  description!: string;

  @IsOptional()
  @IsUUID()
  assignedToUserId?: string;

  @IsOptional()
  @IsDateString()
  dueAt?: string;
}
