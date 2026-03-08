import { IsOptional, IsString } from 'class-validator';

export class AdminMarcarPagoPagadoDto {
  @IsOptional()
  @IsString()
  fechaPago?: string;
}
