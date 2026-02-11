import { Punch, PunchType } from '@prisma/client';

export interface AttendanceConfig {
  scheduledStartMinutes: number;
  scheduledEndMinutes: number;
  lunchExpectedMinutes: number;
  permisoExpectedMinutes: number;
  workdayMinutes: number;
  weekendDays: number[];
}

export const defaultAttendanceConfig: AttendanceConfig = {
  scheduledStartMinutes: 9 * 60,
  scheduledEndMinutes: 18 * 60,
  lunchExpectedMinutes: 60,
  permisoExpectedMinutes: 60,
  workdayMinutes: 8 * 60,
  weekendDays: [0],
};

export type AttendanceIncidentType = 'TARDY' | 'EARLY' | 'INCOMPLETE';

export interface AttendanceIncidentMetrics {
  type: AttendanceIncidentType;
  minutes: number;
  referenceTime?: Date;
}

export interface AttendanceDayMetrics {
  date: string;
  entry?: Date;
  exit?: Date;
  lunchMinutes: number;
  lunchComplete: boolean;
  permisoMinutes: number;
  permisoComplete: boolean;
  tardinessMinutes: number;
  earlyLeaveMinutes: number;
  workedMinutesNet?: number;
  notWorkedMinutes: number;
  incomplete: boolean;
  isWeekend: boolean;
  incidents: AttendanceIncidentMetrics[];
}

type PairResult = {
  start?: Punch;
  end?: Punch;
};

export class AttendanceCalculator {
  // Dominican Republic time: UTC-4 year-round (America/Santo_Domingo). No DST.
  private static readonly RD_OFFSET_MS = 4 * 60 * 60 * 1000;

  private static toDominicanLocal(date: Date): Date {
    return new Date(date.getTime() - this.RD_OFFSET_MS);
  }

  static computeDayMetrics(
    dateKey: string,
    punches: Punch[],
    config: AttendanceConfig = defaultAttendanceConfig
  ): AttendanceDayMetrics {
    const sorted = [...punches].sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime());
    const entry = this.findFirst(sorted, PunchType.ENTRADA_LABOR);
    const exit = this.findLast(sorted, PunchType.SALIDA_LABOR);
    const isWeekend = this.isWeekend(dateKey, config);
    const lunchPair = this.pairPunches(sorted, PunchType.SALIDA_ALMUERZO, PunchType.ENTRADA_ALMUERZO);
    const permisoPair = this.pairPunches(sorted, PunchType.SALIDA_PERMISO, PunchType.ENTRADA_PERMISO);
    const lunch = this.durationMinutes(lunchPair, config.lunchExpectedMinutes);
    const permiso = this.durationMinutes(permisoPair, config.permisoExpectedMinutes);

    const tardinessMinutes = entry && !isWeekend
      ? Math.max(0, this.minutesSinceMidnight(entry.timestamp) - config.scheduledStartMinutes)
      : 0;

    const earlyLeaveMinutes = exit && !isWeekend
      ? Math.max(0, config.scheduledEndMinutes - this.minutesSinceMidnight(exit.timestamp))
      : 0;

    const workedMinutesNet = entry && exit
      ? Math.max(0, this.diffMinutes(exit.timestamp, entry.timestamp) - lunch.minutes - permiso.minutes)
      : undefined;

    const incomplete = !entry || !exit;
    const notWorkedMinutes = this.calculateNotWorked(config, isWeekend, incomplete, workedMinutesNet);

    const incidents = this.buildIncidents(
      config,
      isWeekend,
      tardinessMinutes,
      earlyLeaveMinutes,
      incomplete,
      entry,
      exit
    );

    return {
      date: dateKey,
      entry: entry?.timestamp,
      exit: exit?.timestamp,
      lunchMinutes: lunch.minutes,
      lunchComplete: lunch.complete,
      permisoMinutes: permiso.minutes,
      permisoComplete: permiso.complete,
      tardinessMinutes,
      earlyLeaveMinutes,
      workedMinutesNet,
      notWorkedMinutes,
      incomplete,
      isWeekend,
      incidents,
    };
  }

  static groupByDay(punches: Punch[]): Map<string, Punch[]> {
    const map = new Map<string, Punch[]>();
    for (const punch of punches) {
      const key = this.toDayKey(punch.timestamp);
      const bucket = map.get(key) ?? [];
      bucket.push(punch);
      map.set(key, bucket);
    }
    return map;
  }

  static toDayKey(date: Date): string {
    return this.toDominicanLocal(date).toISOString().substring(0, 10);
  }

  private static isWeekend(dateKey: string, config: AttendanceConfig): boolean {
    const localMidnight = new Date(`${dateKey}T00:00:00-04:00`);
    return config.weekendDays.includes(localMidnight.getUTCDay());
  }

  private static findFirst(punches: Punch[], type: PunchType): Punch | undefined {
    return punches.find((p) => p.type === type);
  }

  private static findLast(punches: Punch[], type: PunchType): Punch | undefined {
    for (let i = punches.length - 1; i >= 0; i--) {
      if (punches[i].type === type) return punches[i];
    }
    return undefined;
  }

  private static pairPunches(punches: Punch[], startType: PunchType, endType: PunchType): PairResult {
    const start = this.findFirst(punches, startType);
    if (!start) return { start };
    const end = punches.find((p) => p.type === endType && p.timestamp.getTime() > start.timestamp.getTime());
    return { start, end };
  }

  private static durationMinutes(pair: PairResult, fallback: number) {
    if (pair.start && pair.end) {
      return { minutes: Math.max(0, this.diffMinutes(pair.end.timestamp, pair.start.timestamp)), complete: true };
    }
    if (pair.start || pair.end) {
      return { minutes: fallback, complete: false };
    }
    return { minutes: 0, complete: true };
  }

  private static diffMinutes(end: Date, start: Date) {
    return Math.round((end.getTime() - start.getTime()) / 60000);
  }

  private static minutesSinceMidnight(date: Date) {
    const local = this.toDominicanLocal(date);
    return local.getUTCHours() * 60 + local.getUTCMinutes();
  }

  private static calculateNotWorked(
    config: AttendanceConfig,
    isWeekend: boolean,
    incomplete: boolean,
    workedMinutes?: number
  ) {
    if (isWeekend) {
      return 0;
    }
    if (incomplete || workedMinutes == null) {
      return config.workdayMinutes;
    }
    return Math.max(0, config.workdayMinutes - workedMinutes);
  }

  private static buildIncidents(
    config: AttendanceConfig,
    isWeekend: boolean,
    tardinessMinutes: number,
    earlyLeaveMinutes: number,
    incomplete: boolean,
    entry?: Punch,
    exit?: Punch
  ): AttendanceIncidentMetrics[] {
    if (isWeekend) {
      return [];
    }

    const incidents: AttendanceIncidentMetrics[] = [];
    if (tardinessMinutes > 0) {
      incidents.push({
        type: 'TARDY',
        minutes: tardinessMinutes,
        referenceTime: entry?.timestamp,
      });
    }
    if (earlyLeaveMinutes > 0) {
      incidents.push({
        type: 'EARLY',
        minutes: earlyLeaveMinutes,
        referenceTime: exit?.timestamp,
      });
    }
    if (incomplete) {
      incidents.push({
        type: 'INCOMPLETE',
        minutes: config.workdayMinutes,
        referenceTime: entry?.timestamp ?? exit?.timestamp,
      });
    }
    return incidents;
  }
}
