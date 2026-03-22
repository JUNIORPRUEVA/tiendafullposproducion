import { IsString } from 'class-validator';

export class CreateReportDto {
  @IsString()
  report!: string;
}