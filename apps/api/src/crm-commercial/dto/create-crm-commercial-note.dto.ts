import { IsString, MaxLength } from 'class-validator';

export class CreateCrmCommercialNoteDto {
  @IsString()
  @MaxLength(5000)
  note!: string;
}
