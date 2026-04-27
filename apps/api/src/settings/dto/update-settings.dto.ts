import { IsArray, IsBoolean, IsOptional, IsString, MaxLength, ValidateNested } from 'class-validator';
import { Type } from 'class-transformer';

export class BankAccountDto {
  @IsOptional()
  @IsString()
  @MaxLength(200)
  name?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  type?: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  accountNumber?: string;

  @IsOptional()
  @IsString()
  @MaxLength(200)
  bankName?: string;
}

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
  @MaxLength(60)
  phonePreferential?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  address?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  description?: string;

  @IsOptional()
  @IsString()
  @MaxLength(300)
  instagramUrl?: string;

  @IsOptional()
  @IsString()
  @MaxLength(300)
  facebookUrl?: string;

  @IsOptional()
  @IsString()
  @MaxLength(300)
  websiteUrl?: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  gpsLocationUrl?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  businessHours?: string;

  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => BankAccountDto)
  bankAccounts?: BankAccountDto[];

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

  @IsOptional()
  @IsBoolean()
  whatsappWebhookEnabled?: boolean;

  @IsOptional()
  @IsBoolean()
  operationsTechCanViewAllServices?: boolean;
}

