import { IsIn, IsOptional, IsString, IsUUID, MaxLength, ValidateIf } from 'class-validator';

const checklistTemplateTypes = ['herramientas', 'productos', 'instalacion'] as const;

export class CreateServiceChecklistTemplateDto {
  @IsOptional()
  @ValidateIf((_, value) => typeof value === 'string' && value.trim().length > 0)
  @IsUUID()
  categoryId?: string;

  @IsOptional()
  @ValidateIf((_, value) => typeof value === 'string' && value.trim().length > 0)
  @IsUUID()
  phaseId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  categoryCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  phaseCode?: string;

  @IsString()
  @IsIn(checklistTemplateTypes)
  type!: (typeof checklistTemplateTypes)[number];

  @IsOptional()
  @IsString()
  @MaxLength(160)
  title?: string;
}
