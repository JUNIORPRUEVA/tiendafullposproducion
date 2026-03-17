import { IsNotEmpty, IsString, IsUUID, MaxLength } from 'class-validator';

export class CreateServiceChecklistTemplateDto {
  @IsUUID()
  categoryId!: string;

  @IsUUID()
  phaseId!: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(160)
  title!: string;
}
