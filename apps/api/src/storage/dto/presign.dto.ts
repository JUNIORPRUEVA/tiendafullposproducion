import { IsIn, IsInt, IsNotEmpty, IsString, IsUUID, Max, Min } from 'class-validator';
import { ALLOWED_CONTENT_TYPES, ALLOWED_KINDS } from '../helpers/storage_helpers';

export class PresignStorageDto {
  @IsUUID()
  serviceId!: string;

  @IsString()
  @IsNotEmpty()
  fileName!: string;

  @IsString()
  @IsIn(ALLOWED_CONTENT_TYPES as unknown as string[])
  contentType!: string;

  @IsString()
  @IsIn(ALLOWED_KINDS as unknown as string[])
  kind!: string;

  @IsInt()
  @Min(1)
  // Guardrail (actual limits are enforced per media type in service).
  @Max(250 * 1024 * 1024)
  fileSize!: number;

  @IsUUID()
  executionReportId?: string;
}
