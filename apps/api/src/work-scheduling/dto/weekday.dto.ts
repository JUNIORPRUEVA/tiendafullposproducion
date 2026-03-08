import { IsInt, Max, Min } from 'class-validator';

export class WeekdayDto {
  @IsInt()
  @Min(0)
  @Max(6)
  weekday!: number;
}
