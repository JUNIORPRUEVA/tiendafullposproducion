import { Transform } from 'class-transformer';
import { IsNumber, IsOptional, IsString, Max, Min } from 'class-validator';

const toOptionalNumber = ({ value }: { value: unknown }) => {
  if (value === undefined || value === null || value === '') return undefined;
  const numeric = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(numeric) ? numeric : value;
};

const toOptionalString = ({ value, obj }: { value: unknown; obj?: Record<string, unknown> }) => {
  const resolved = value ?? obj?.locationUrl ?? obj?.location_url;
  if (resolved === undefined || resolved === null) return undefined;
  const normalized = String(resolved).trim();
  return normalized.length > 0 ? normalized : undefined;
};

export class ClientLocationFieldsDto {
  @IsOptional()
  @Transform(toOptionalNumber)
  @IsNumber()
  @Min(-90)
  @Max(90)
  latitude?: number | null;

  @IsOptional()
  @Transform(toOptionalNumber)
  @IsNumber()
  @Min(-180)
  @Max(180)
  longitude?: number | null;

  @IsOptional()
  @Transform(toOptionalString)
  @IsString()
  location_url?: string | null;

  @IsOptional()
  @Transform(toOptionalString)
  @IsString()
  locationUrl?: string | null;
}