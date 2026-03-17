import { IsInt, IsNotEmpty, IsOptional, IsString, MaxLength, Min } from 'class-validator';

export class CreateServiceChecklistPhaseDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(120)
  name!: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  code?: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  orderIndex?: number;
}
