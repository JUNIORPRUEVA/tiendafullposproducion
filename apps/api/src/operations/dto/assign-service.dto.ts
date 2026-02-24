import { Type } from 'class-transformer';
import { ArrayMinSize, IsArray, IsIn, IsUUID, ValidateNested } from 'class-validator';

export class AssignServiceItemDto {
  @IsUUID()
  userId!: string;

  @IsIn(['lead', 'assistant'])
  role!: 'lead' | 'assistant';
}

export class AssignServiceDto {
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => AssignServiceItemDto)
  assignments!: AssignServiceItemDto[];
}