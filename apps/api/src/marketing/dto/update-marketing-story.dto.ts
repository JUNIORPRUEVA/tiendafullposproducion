import { IsArray, IsOptional, IsString } from 'class-validator';

export class UpdateMarketingStoryDto {
  @IsOptional()
  @IsString()
  title?: string;

  @IsOptional()
  @IsString()
  shortText?: string;

  @IsOptional()
  @IsString()
  longText?: string;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  hashtags?: string[];

  @IsOptional()
  @IsString()
  imagePrompt?: string;

  @IsOptional()
  @IsString()
  imageUrl?: string;

  @IsOptional()
  @IsString()
  mediaAssetId?: string;

  @IsOptional()
  @IsString()
  visualConcept?: string;

  @IsOptional()
  @IsString()
  designNotes?: string;

  @IsOptional()
  @IsString()
  usedResearchAngle?: string;

  @IsOptional()
  @IsString()
  usedOffer?: string;

  @IsOptional()
  @IsString()
  usedCTA?: string;
}
