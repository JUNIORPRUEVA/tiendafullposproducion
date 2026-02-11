import { IsString } from 'class-validator';

export class CreateClientDto {
  @IsString()
  nombre!: string;

  @IsString()
  telefono!: string;
}

