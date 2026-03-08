import { IsNotEmpty, IsString, IsUUID } from 'class-validator';

export class AdminCrearPagoPeriodoDto {
  @IsUUID()
  tecnicoId!: string;

  @IsString()
  @IsNotEmpty()
  fechaInicio!: string;

  @IsString()
  @IsNotEmpty()
  fechaFin!: string;
}
