import { IsOptional, IsString, MaxLength } from 'class-validator';

export class SuggestCrmCommercialOrthographyDto {
  @IsString()
  @MaxLength(4000)
  text!: string;

  @IsOptional()
  @IsString()
  @MaxLength(4000)
  previousText?: string;
}
