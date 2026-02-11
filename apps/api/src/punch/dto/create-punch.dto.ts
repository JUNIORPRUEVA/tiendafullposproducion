import { IsEnum } from 'class-validator';
import { PunchType } from '@prisma/client';

export class CreatePunchDto {
  @IsEnum(PunchType)
  type!: PunchType;
}
