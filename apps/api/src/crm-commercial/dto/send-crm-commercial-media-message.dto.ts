import { IsString, IsNotEmpty, IsOptional, IsEnum, IsNumber, Max } from 'class-validator';

export enum CrmCommercialMediaType {
  IMAGE = 'image',
  VIDEO = 'video',
  AUDIO = 'audio',
  DOCUMENT = 'document',
}

export class SendCrmCommercialMediaMessageDto {
  @IsString()
  @IsNotEmpty()
  mediaType!: string; // 'image' | 'video' | 'audio' | 'document'

  @IsString()
  @IsNotEmpty()
  mimeType!: string; // 'image/jpeg', 'video/mp4', 'audio/mpeg', 'application/pdf', etc.

  @IsString()
  @IsNotEmpty()
  fileName!: string; // Original file name

  @IsString()
  @IsNotEmpty()
  base64Data!: string; // Base64-encoded file content

  @IsOptional()
  @IsString()
  caption?: string; // Optional caption for media

  @IsNumber()
  @IsOptional()
  @Max(100 * 1024 * 1024) // Max 100MB
  fileSizeBytes?: number; // File size in bytes for validation
}

export class StartCrmCommercialMediaMessageDto
  extends SendCrmCommercialMediaMessageDto {
  @IsString()
  @IsNotEmpty()
  phone!: string; // Destination phone number
}

export class ReplyCrmCommercialMediaMessageDto extends SendCrmCommercialMediaMessageDto {}
