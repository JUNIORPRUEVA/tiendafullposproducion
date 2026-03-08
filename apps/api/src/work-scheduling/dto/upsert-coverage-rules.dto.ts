import { IsArray, IsEnum, IsInt, Max, Min, ValidateNested } from 'class-validator';
import { Type } from 'class-transformer';
import { Role } from '@prisma/client';

export class UpsertCoverageRuleDto {
  @IsEnum(Role)
  role!: Role;

  @IsInt()
  @Min(0)
  @Max(6)
  weekday!: number;

  @IsInt()
  @Min(0)
  min_required!: number;
}

export class UpsertCoverageRulesDto {
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => UpsertCoverageRuleDto)
  rules!: UpsertCoverageRuleDto[];
}
