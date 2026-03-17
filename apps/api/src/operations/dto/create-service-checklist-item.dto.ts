import { IsBoolean, IsInt, IsNotEmpty, IsOptional, IsString, IsUUID, MaxLength, Min } from 'class-validator';

export class CreateServiceChecklistItemDto {
  @IsUUID()
  templateId!: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(240)
  label!: string;

  @IsOptional()
  @IsBoolean()
  isRequired?: boolean;

  @IsOptional()
  @IsInt()
  @Min(0)
  orderIndex?: number;
}
