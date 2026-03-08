import { IsDateString, IsOptional, IsUUID } from 'class-validator';

export class AuditQueryDto {
  @IsOptional()
  @IsUUID()
  target_user_id?: string;

  @IsOptional()
  @IsDateString()
  from?: string;

  @IsOptional()
  @IsDateString()
  to?: string;
}
