import { ArrayMaxSize, IsArray, IsDateString, IsOptional, IsString } from 'class-validator';

export class GenerateMarketingStoriesDto {
  @IsOptional()
  @IsDateString()
  date?: string;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(3)
  @IsString({ each: true })
  selected_media_asset_ids?: string[];
}
