import {
  IsDateString,
  IsEnum,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  MinLength,
} from 'class-validator';
import { FollowupTaskPriority } from './create-crm-commercial-followup-task.dto';

export class UpdateCrmCommercialFollowupTaskDto {
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(200)
  title?: string;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  description?: string;

  @IsOptional()
  @IsDateString()
  dueDate?: string;

  @IsOptional()
  @IsEnum(FollowupTaskPriority)
  priority?: FollowupTaskPriority;

  @IsOptional()
  @IsUUID()
  assignedUserId?: string;
}
