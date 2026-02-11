import { IsBoolean, IsOptional } from 'class-validator';
import { AdminPunchQueryDto } from './admin-punch-query.dto';

export class AttendanceSummaryQueryDto extends AdminPunchQueryDto {
  @IsOptional()
  @IsBoolean()
  incidentsOnly?: boolean;
}
