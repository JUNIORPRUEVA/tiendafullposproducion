import { Transform } from 'class-transformer';
import { IsIn, IsOptional, IsString, Max, Min } from 'class-validator';

const MEDIA_GALLERY_TYPE_VALUES = ['all', 'image', 'video'] as const;
const MEDIA_GALLERY_INSTALLATION_VALUES = [
  'all',
  'completed',
  'pending',
] as const;

export type MediaGalleryTypeFilter = (typeof MEDIA_GALLERY_TYPE_VALUES)[number];
export type MediaGalleryInstallationFilter =
  (typeof MEDIA_GALLERY_INSTALLATION_VALUES)[number];

function normalizeString(value: unknown): string | undefined {
  if (typeof value !== 'string') return undefined;
  const valueTrimmed = value.trim().toLowerCase();
  return valueTrimmed.length > 0 ? valueTrimmed : undefined;
}

function normalizeLimit(value: unknown): number {
  const parsed = Number.parseInt(`${value ?? ''}`.trim(), 10);
  if (!Number.isFinite(parsed)) return 48;
  return parsed;
}

export class MediaGalleryQueryDto {
  @IsOptional()
  @Transform(({ value }) => normalizeString(value) ?? 'all')
  @IsIn(MEDIA_GALLERY_TYPE_VALUES)
  type: MediaGalleryTypeFilter = 'all';

  @IsOptional()
  @Transform(({ value }) => normalizeString(value) ?? 'all')
  @IsIn(MEDIA_GALLERY_INSTALLATION_VALUES)
  installationStatus: MediaGalleryInstallationFilter = 'all';

  @IsOptional()
  @Transform(({ value }) => normalizeLimit(value))
  @Min(12)
  @Max(120)
  limit = 48;

  @IsOptional()
  @Transform(({ value }) => normalizeString(value))
  @IsString()
  cursor?: string;
}