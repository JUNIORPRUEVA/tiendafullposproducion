import { IsNotEmpty, IsOptional, IsString } from 'class-validator';

export class AdminAprobarRechazarDto {
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  observacion?: string;
}

export class AdminRechazarDto {
  @IsString()
  @IsNotEmpty()
  observacion!: string;
}
