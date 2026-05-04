import { IsDateString, IsOptional } from 'class-validator';

export class GenerateMarketingStoriesDto {
  @IsOptional()
  @IsDateString()
  date?: string;
}
