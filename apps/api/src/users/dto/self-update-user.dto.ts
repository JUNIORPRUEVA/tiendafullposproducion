import { IsEmail, IsOptional, IsString, MinLength } from 'class-validator';

export class SelfUpdateUserDto {
  @IsOptional()
  @IsEmail()
  email?: string;

  @IsOptional()
  @IsString()
  nombreCompleto?: string;

  @IsOptional()
  @IsString()
  telefono?: string;

  @IsOptional()
  @IsString()
  @MinLength(8)
  password?: string;
}
