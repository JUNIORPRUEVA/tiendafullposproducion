import { IsString, IsUrl, MinLength } from 'class-validator';

export class SignWorkContractDto {
  @IsString()
  @MinLength(3)
  version!: string;

  @IsString()
  @MinLength(3)
  // Accept absolute or relative URLs. If absolute, it must still be a string.
  // NOTE: We do not enforce URL format strictly because deployments may use relative /uploads paths.
  signatureUrl!: string;
}
