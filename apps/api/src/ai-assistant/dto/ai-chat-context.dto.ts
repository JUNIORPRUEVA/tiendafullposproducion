import { IsOptional, IsString } from 'class-validator';

export class AiChatContextDto {
  @IsString()
  module!: string;

  @IsOptional()
  @IsString()
  screenName?: string;

  @IsOptional()
  @IsString()
  route?: string;

  // Optional contextual entity. E.g. a clientId when user opened the assistant from a client detail.
  @IsOptional()
  @IsString()
  entityType?: string;

  @IsOptional()
  @IsString()
  entityId?: string;
}
