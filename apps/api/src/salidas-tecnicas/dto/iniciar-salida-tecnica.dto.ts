import { Type } from 'class-transformer';
import { IsBoolean, IsNotEmpty, IsNumber, IsOptional, IsString, IsUUID } from 'class-validator';

export class IniciarSalidaTecnicaDto {
  @IsUUID()
  servicioId!: string;

  @IsUUID()
  vehiculoId!: string;

  @IsBoolean()
  esVehiculoPropio!: boolean;

  @Type(() => Number)
  @IsNumber()
  latSalida!: number;

  @Type(() => Number)
  @IsNumber()
  lngSalida!: number;

  @IsOptional()
  @IsString()
  @IsNotEmpty()
  observacion?: string;
}
