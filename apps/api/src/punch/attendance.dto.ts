import { Punch, Role } from '@prisma/client';
import { AttendanceDayMetrics } from './attendance-calculator';

export interface AttendanceSummaryTotals {
  tardyCount: number;
  earlyLeaveCount: number;
  incompleteCount: number;
  workedMinutes: number;
  favorableMinutes: number;
  unfavorableMinutes: number;
  balanceMinutes: number;
  notWorkedMinutes: number;
}

export interface AttendanceAggregateMetrics {
  tardinessMinutes: number;
  earlyLeaveMinutes: number;
  notWorkedMinutes: number;
  workedMinutes: number;
  favorableMinutes: number;
  unfavorableMinutes: number;
  balanceMinutes: number;
  incompleteDays: number;
  incidentsCount: number;
}

export interface AttendanceSummaryUser {
  user: {
    id: string;
    email: string;
    nombreCompleto: string;
    role: Role;
  };
  days: AttendanceDayMetrics[];
  aggregate: AttendanceAggregateMetrics;
}

export interface AttendanceSummaryResponse {
  totals: AttendanceSummaryTotals;
  users: AttendanceSummaryUser[];
  perDay?: AttendanceDayMetrics[];
}

export interface AttendanceDetailResponse {
  user: {
    id: string;
    email: string;
    nombreCompleto: string;
    role: Role;
  };
  punches: Punch[];
  days: AttendanceDayMetrics[];
  totals: AttendanceAggregateMetrics;
}
