import { IsNotEmpty, IsOptional, IsString, MaxLength } from 'class-validator';

export class CreateServiceChecklistCategoryDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(120)
  name!: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  code?: string;
}
