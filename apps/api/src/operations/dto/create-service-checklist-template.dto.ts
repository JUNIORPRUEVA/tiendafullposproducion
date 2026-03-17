import { IsIn, IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';

const checklistTemplateTypes = ['herramientas', 'productos', 'instalacion'] as const;

export class CreateServiceChecklistTemplateDto {
  @IsUUID()
  categoryId!: string;

  @IsUUID()
  phaseId!: string;

  @IsString()
  @IsIn(checklistTemplateTypes)
  type!: (typeof checklistTemplateTypes)[number];

  @IsOptional()
  @IsString()
  @MaxLength(160)
  title?: string;
}
