import { IsBoolean, IsInt, IsOptional, IsString, Max, Min } from 'class-validator';

export class UpdateMarketingResearchConfigDto {
  @IsOptional()
  @IsString()
  default_research_prompt?: string;

  @IsOptional()
  @IsString()
  business_name?: string;

  @IsOptional()
  @IsString()
  business_location?: string;

  @IsOptional()
  @IsString()
  business_description?: string;

  @IsOptional()
  @IsString({ each: true })
  main_services?: string[];

  @IsOptional()
  @IsString({ each: true })
  priority_services?: string[];

  @IsOptional()
  @IsString()
  target_market?: string;

  @IsOptional()
  @IsString()
  brand_tone?: string;

  @IsOptional()
  @IsBoolean()
  learning_enabled?: boolean;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(30)
  research_frequency_days?: number;

  @IsOptional()
  @IsBoolean()
  require_approval?: boolean;
}

export class GenerateResearchDto {
  @IsOptional()
  @IsString()
  custom_prompt?: string;
}
