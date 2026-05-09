import { IsBoolean, IsNotEmpty, IsOptional, IsString, ValidateIf } from 'class-validator';

export class UpdateCrmCommercialSettingsDto {
  @IsOptional()
  @IsBoolean()
  enabled?: boolean;

  @ValidateIf((dto: UpdateCrmCommercialSettingsDto) => dto.selectedWhatsappInstanceId != null)
  @IsString()
  @IsNotEmpty()
  selectedWhatsappInstanceId?: string;

  @ValidateIf((dto: UpdateCrmCommercialSettingsDto) => dto.selectedWhatsappInstanceName != null)
  @IsString()
  @IsNotEmpty()
  selectedWhatsappInstanceName?: string;
}
