import { Transform } from 'class-transformer';
import { IsInt, IsOptional, IsString, Min } from 'class-validator';

const toSafePositiveIntOrUndefined = (value: unknown) => {
  if (value === undefined || value === null) return undefined;
  const num = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(num)) return undefined;
  return Math.max(1, Math.trunc(num));
};

export class ClientsQueryDto {
  @IsOptional()
  @IsString()
  search?: string;

  @IsOptional()
  @Transform(({ value }) => toSafePositiveIntOrUndefined(value))
  @IsInt()
  @Min(1)
  page?: number;

  @IsOptional()
  @Transform(({ value }) => toSafePositiveIntOrUndefined(value))
  @IsInt()
  @Min(1)
  pageSize?: number;
}
