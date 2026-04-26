import { IsOptional, IsString, MinLength } from 'class-validator';

export class CreateWhatsappInstanceDto {
  @IsOptional()
  @IsString()
  @MinLength(3)
  instanceName?: string;

  @IsOptional()
  @IsString()
  phoneNumber?: string;
}
