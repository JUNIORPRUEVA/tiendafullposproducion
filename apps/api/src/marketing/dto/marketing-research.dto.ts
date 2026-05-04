import { IsBoolean, IsInt, IsNumber, IsOptional, IsString, Max, Min } from 'class-validator';

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

  // ── New company profile fields ────────────────────────────────────────────

  @IsOptional()
  @IsString()
  phone?: string;

  @IsOptional()
  @IsString()
  address?: string;

  @IsOptional()
  @IsString()
  city?: string;

  @IsOptional()
  @IsString()
  province?: string;

  @IsOptional()
  @IsString()
  country?: string;

  @IsOptional()
  @IsNumber()
  latitude?: number;

  @IsOptional()
  @IsNumber()
  longitude?: number;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(1000)
  service_radius_km?: number;

  @IsOptional()
  @IsString({ each: true })
  service_zones?: string[];

  @IsOptional()
  @IsString()
  default_cta?: string;

  @IsOptional()
  @IsString({ each: true })
  brand_colors?: string[];

  @IsOptional()
  @IsString()
  business_hours?: string;

  @IsOptional()
  @IsString()
  internal_notes?: string;
}

export class GenerateResearchDto {
  @IsOptional()
  @IsString()
  custom_prompt?: string;
}
