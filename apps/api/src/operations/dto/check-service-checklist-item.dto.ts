import { IsBoolean } from 'class-validator';

export class CheckServiceChecklistItemDto {
  @IsBoolean()
  isChecked!: boolean;
}
