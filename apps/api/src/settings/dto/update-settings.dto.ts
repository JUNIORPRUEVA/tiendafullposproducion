import { IsOptional, IsString, MaxLength } from 'class-validator';

export class UpdateSettingsDto {
  @IsOptional()
  @IsString()
  @MaxLength(200)
  companyName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  rnc?: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  phone?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  address?: string;

  @IsOptional()
  @IsString()
  @MaxLength(200)
  legalRepresentativeName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  legalRepresentativeCedula?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  legalRepresentativeRole?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  legalRepresentativeNationality?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  legalRepresentativeCivilStatus?: string;

  @IsOptional()
  @IsString()
  logoBase64?: string;

  @IsOptional()
  @IsString()
  openAiApiKey?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  openAiModel?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  evolutionApiBaseUrl?: string;

  @IsOptional()
  @IsString()
  @MaxLength(200)
  evolutionApiInstanceName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  evolutionApiApiKey?: string;
}
