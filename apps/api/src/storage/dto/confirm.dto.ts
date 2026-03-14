import { IsBoolean, IsInt, IsNotEmpty, IsOptional, IsString, IsUUID, Max, Min } from 'class-validator';
import { ALLOWED_KINDS } from '../helpers/storage_helpers';
import { IsIn } from 'class-validator';

export class ConfirmStorageDto {
  @IsUUID()
  serviceId!: string;

  @IsString()
  @IsNotEmpty()
  objectKey!: string;

  @IsString()
  @IsNotEmpty()
  publicUrl!: string;

  @IsString()
  @IsNotEmpty()
  fileName!: string;

  @IsString()
  @IsNotEmpty()
  mimeType!: string;

  @IsInt()
  @Min(1)
  @Max(250 * 1024 * 1024)
  fileSize!: number;

  @IsString()
  @IsIn(ALLOWED_KINDS as unknown as string[])
  kind!: string;

  @IsOptional()
  @IsUUID()
  uploadedByUserId?: string;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(20000)
  width?: number | null;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(20000)
  height?: number | null;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(24 * 60 * 60)
  durationSeconds?: number | null;

  @IsOptional()
  @IsUUID()
  executionReportId?: string | null;

  @IsOptional()
  @IsBoolean()
  isPublic?: boolean;
}
