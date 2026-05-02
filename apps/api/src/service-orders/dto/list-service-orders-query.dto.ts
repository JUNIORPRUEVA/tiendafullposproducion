import { Transform } from 'class-transformer';
import { IsDateString, IsIn, IsOptional } from 'class-validator';
import { SERVICE_ORDER_STATUS_VALUES } from '../service-orders.constants';

function normalizeStatuses(input: unknown): string[] | undefined {
  if (input == null) return undefined;

  const values = Array.isArray(input)
    ? input
    : String(input)
        .split(',')
        .map((part) => part.trim())
        .filter((part) => part.length > 0);

  const unique = Array.from(
    new Set(values.map((value) => String(value).trim()).filter((value) => value.length > 0)),
  );

  return unique.length > 0 ? unique : undefined;
}

export class ListServiceOrdersQueryDto {
  @IsOptional()
  @Transform(({ value }) => normalizeStatuses(value))
  @IsIn(SERVICE_ORDER_STATUS_VALUES, { each: true })
  statuses?: string[];

  @IsOptional()
  @IsDateString()
  from?: string;

  @IsOptional()
  @IsDateString()
  to?: string;
}
