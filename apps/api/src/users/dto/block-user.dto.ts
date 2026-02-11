import { IsBoolean, IsOptional } from 'class-validator';

export class BlockUserDto {
  @IsOptional()
  @IsBoolean()
  blocked?: boolean;
}

