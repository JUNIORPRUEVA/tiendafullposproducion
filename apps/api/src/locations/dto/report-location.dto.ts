import { IsISO8601, IsNumber, IsOptional, Max, Min } from 'class-validator';

export class ReportLocationDto {
  @IsNumber()
  @Min(-90)
  @Max(90)
  latitude!: number;

  @IsNumber()
  @Min(-180)
  @Max(180)
  longitude!: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  accuracyMeters?: number;

  @IsOptional()
  @IsNumber()
  altitudeMeters?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(360)
  headingDegrees?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  speedMps?: number;

  @IsOptional()
  @IsISO8601()
  recordedAt?: string;
}
