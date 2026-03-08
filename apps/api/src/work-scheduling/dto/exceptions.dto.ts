import { WorkScheduleExceptionType } from '@prisma/client';
import { IsDateString, IsEnum, IsOptional, IsString, IsUUID } from 'class-validator';

export class CreateWorkExceptionDto {
  @IsOptional()
  @IsUUID()
  user_id?: string;

  @IsEnum(WorkScheduleExceptionType)
  type!: WorkScheduleExceptionType;

  @IsDateString()
  date_from!: string;

  @IsDateString()
  date_to!: string;

  @IsOptional()
  @IsString()
  note?: string;
}

export class UpdateWorkExceptionDto {
  @IsOptional()
  @IsEnum(WorkScheduleExceptionType)
  type?: WorkScheduleExceptionType;

  @IsOptional()
  @IsDateString()
  date_from?: string;

  @IsOptional()
  @IsDateString()
  date_to?: string;

  @IsOptional()
  @IsString()
  note?: string | null;
}
