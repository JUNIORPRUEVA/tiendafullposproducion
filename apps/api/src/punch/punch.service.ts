import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma, Punch, PunchType, Role } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import {
  AttendanceAggregateMetrics,
  AttendanceDetailResponse,
  AttendanceSummaryResponse,
  AttendanceSummaryUser,
} from './attendance.dto';
import { AttendanceCalculator, AttendanceDayMetrics } from './attendance-calculator';
import { AttendanceSummaryQueryDto } from './dto/attendance-summary-query.dto';
import { AttendanceUserQueryDto } from './dto/attendance-user-query.dto';

@Injectable()
export class PunchService {
  constructor(private readonly prisma: PrismaService) {}

  private static readonly RD_OFFSET = '-04:00';

  async create(userId: string, type: PunchType) {
    const now = new Date();
    return this.prisma.punch.create({
      data: {
        userId,
        type,
        timestamp: now,
      },
    });
  }

  async listMine(userId: string, from?: string, to?: string) {
    if (!userId) {
      throw new BadRequestException('Missing user');
    }

    const where: Prisma.PunchWhereInput = {
      userId,
      ...this.buildRange(from, to),
    };
    return this.prisma.punch.findMany({
      where,
      orderBy: { timestamp: 'desc' },
    });
  }

  async listAdmin(userId?: string, from?: string, to?: string) {
    const where = this.buildWhere(userId, from, to);
    return this.prisma.punch.findMany({
      where,
      include: {
        user: {
          select: {
            id: true,
            email: true,
            nombreCompleto: true,
            role: true,
          },
        },
      },
      orderBy: { timestamp: 'desc' },
    });
  }

  async attendanceSummary(query: AttendanceSummaryQueryDto): Promise<AttendanceSummaryResponse> {
    const where = this.buildWhere(query.userId, query.from, query.to);
    const punches = await this.prisma.punch.findMany({
      where,
      include: {
        user: {
          select: {
            id: true,
            email: true,
            nombreCompleto: true,
            role: true,
          },
        },
      },
      orderBy: { timestamp: 'asc' },
    });

    const grouped = new Map<string, Punch[]>();
    for (const punch of punches) {
      const bucket = grouped.get(punch.userId) ?? [];
      bucket.push(punch);
      grouped.set(punch.userId, bucket);
    }

    const totals = {
      tardyCount: 0,
      earlyLeaveCount: 0,
      incompleteCount: 0,
      notWorkedMinutes: 0,
    };

    const users: AttendanceSummaryUser[] = [];
    const perDay: AttendanceDayMetrics[] = [];

    for (const [, userPunches] of grouped) {
      const userInfo = (userPunches[0] as any).user as
        | { id: string; email: string; nombreCompleto: string; role: Role }
        | undefined;
      if (!userInfo) continue;

      const days = this.computeDayMetricsList(userPunches);
      const filteredDays = query.incidentsOnly
        ? days.filter((day) => day.incidents.length > 0)
        : days;

      if (query.incidentsOnly && filteredDays.length === 0) {
        continue;
      }

      for (const day of filteredDays) {
        if (day.tardinessMinutes > 0) {
          totals.tardyCount += 1;
        }
        if (day.earlyLeaveMinutes > 0) {
          totals.earlyLeaveCount += 1;
        }
        if (day.incomplete) {
          totals.incompleteCount += 1;
        }
        totals.notWorkedMinutes += day.notWorkedMinutes;
      }

      const aggregate = this.aggregateDays(filteredDays);
      perDay.push(...filteredDays);

      users.push({
        user: {
          id: userInfo.id,
          email: userInfo.email,
          nombreCompleto: userInfo.nombreCompleto,
          role: userInfo.role,
        },
        days: filteredDays,
        aggregate,
      });
    }

    users.sort((a, b) => b.aggregate.incidentsCount - a.aggregate.incidentsCount);
    perDay.sort((a, b) => b.date.localeCompare(a.date));

    return { totals, users, perDay };
  }

  async attendanceDetail(userId: string, query: AttendanceUserQueryDto): Promise<AttendanceDetailResponse> {
    const where = this.buildWhere(userId, query.from, query.to);
    const punches = await this.prisma.punch.findMany({
      where,
      orderBy: { timestamp: 'asc' },
    });

    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        nombreCompleto: true,
        role: true,
      },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    const days = this.computeDayMetricsList(punches);
    const totals = this.aggregateDays(days);

    return { user, punches, days, totals };
  }

  private computeDayMetricsList(punches: Punch[]): AttendanceDayMetrics[] {
    if (!punches.length) {
      return [];
    }

    const grouped = AttendanceCalculator.groupByDay(punches);
    return Array.from(grouped.entries())
      .map(([date, list]) => AttendanceCalculator.computeDayMetrics(date, list))
      .sort((a, b) => b.date.localeCompare(a.date));
  }

  private aggregateDays(days: AttendanceDayMetrics[]): AttendanceAggregateMetrics {
    const aggregate: AttendanceAggregateMetrics = {
      tardinessMinutes: 0,
      earlyLeaveMinutes: 0,
      notWorkedMinutes: 0,
      workedMinutes: 0,
      incompleteDays: 0,
      incidentsCount: 0,
    };

    for (const day of days) {
      aggregate.tardinessMinutes += day.tardinessMinutes;
      aggregate.earlyLeaveMinutes += day.earlyLeaveMinutes;
      aggregate.notWorkedMinutes += day.notWorkedMinutes;
      aggregate.workedMinutes += day.workedMinutesNet ?? 0;
      if (day.incomplete) {
        aggregate.incompleteDays += 1;
      }
      aggregate.incidentsCount += day.incidents.length;
    }

    return aggregate;
  }

  private buildWhere(userId?: string, from?: string, to?: string): Prisma.PunchWhereInput {
    const where: Prisma.PunchWhereInput = {};
    if (userId) {
      where.userId = userId;
    }
    const timestamp = this.buildRange(from, to);
    if (timestamp) {
      where.timestamp = timestamp;
    }
    return where;
  }

  private buildRange(from?: string, to?: string) {
    const range: Prisma.DateTimeFilter = {};
    if (from) {
      const d = this.parseDateInput(from, true);
      if (Number.isNaN(d.getTime())) throw new BadRequestException('Invalid from');
      range.gte = d;
    }
    if (to) {
      const d = this.parseDateInput(to, false);
      if (Number.isNaN(d.getTime())) throw new BadRequestException('Invalid to');
      range.lt = d;
    }
    return Object.keys(range).length ? range : undefined;
  }

  private parseDateInput(value: string, isStart: boolean): Date {
    const v = value.trim();
    const isDateOnly = /^\d{4}-\d{2}-\d{2}$/.test(v);
    if (isDateOnly) {
      const start = new Date(`${v}T00:00:00${PunchService.RD_OFFSET}`);
      if (Number.isNaN(start.getTime())) {
        return new Date('invalid');
      }
      if (isStart) {
        return start;
      }
      return new Date(start.getTime() + 24 * 60 * 60 * 1000);
    }
    return new Date(v);
  }
}
