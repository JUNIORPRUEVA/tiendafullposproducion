import { IsIn, IsOptional, IsString } from 'class-validator';
import { ALLOWED_KINDS } from '../helpers/storage_helpers';

export class ServiceMediaQueryDto {
  @IsOptional()
  @IsString()
  @IsIn(ALLOWED_KINDS as unknown as string[])
  kind?: string;

  @IsOptional()
  @IsString()
  @IsIn(['image', 'video', 'document'])
  mediaType?: string;
}
