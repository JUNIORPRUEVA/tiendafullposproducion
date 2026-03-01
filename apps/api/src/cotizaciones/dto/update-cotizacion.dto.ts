import { Type } from 'class-transformer';
import { IsArray, IsBoolean, IsNumber, IsOptional, IsString, IsUUID, Min, ValidateNested } from 'class-validator';
import { CreateCotizacionItemDto } from './create-cotizacion.dto';

export class UpdateCotizacionDto {
	@IsOptional()
	@IsUUID()
	customerId?: string;

	@IsOptional()
	@IsString()
	customerName?: string;

	@IsOptional()
	@IsString()
	customerPhone?: string;

	@IsOptional()
	@IsString()
	note?: string;

	@IsOptional()
	@IsBoolean()
	includeItbis?: boolean;

	@IsOptional()
	@Type(() => Number)
	@IsNumber()
	@Min(0)
	itbisRate?: number;

	@IsOptional()
	@IsArray()
	@ValidateNested({ each: true })
	@Type(() => CreateCotizacionItemDto)
	items?: CreateCotizacionItemDto[];
}
