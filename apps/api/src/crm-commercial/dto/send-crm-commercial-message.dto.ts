import { IsNotEmpty, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

export class SendCrmCommercialMessageDto {
  @IsString()
  @IsOptional()
  @MinLength(7)
  @MaxLength(32)
  phone?: string;

  @IsString()
  @IsOptional()
  @MinLength(3)
  @MaxLength(120)
  conversationId?: string;

  @IsString()
  @IsNotEmpty()
  @MinLength(1)
  @MaxLength(4096)
  text!: string;
}
