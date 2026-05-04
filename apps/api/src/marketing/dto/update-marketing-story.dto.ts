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
}
