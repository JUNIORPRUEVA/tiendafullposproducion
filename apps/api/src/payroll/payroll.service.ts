import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PayrollEntryType, PayrollPeriodStatus, Prisma, Role } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { AddPayrollEntryDto } from './dto/payroll-entry.dto';
import { UpsertPayrollConfigDto } from './dto/upsert-payroll-config.dto';
import { UpsertPayrollEmployeeDto } from './dto/upsert-payroll-employee.dto';

@Injectable()
export class PayrollService {
  constructor(private readonly prisma: PrismaService) {}

  async resolveCompanyOwnerId(fallbackUserId: string) {
    const admin = await this.prisma.user.findFirst({
      where: { role: Role.ADMIN },
      orderBy: { createdAt: 'asc' },
      select: { id: true },
    });
    return admin?.id ?? fallbackUserId;
  }

  async listPeriods(ownerId: string) {
    return this.prisma.payrollPeriod.findMany({
      where: { ownerId },
      orderBy: { startDate: 'desc' },
    });
  }

  async getPeriodById(ownerId: string, periodId: string) {
    return this.prisma.payrollPeriod.findFirst({ where: { ownerId, id: periodId } });
  }

  async hasOverlappingOpenPeriod(ownerId: string, start: Date, end: Date) {
    const count = await this.prisma.payrollPeriod.count({
      where: {
        ownerId,
        status: PayrollPeriodStatus.OPEN,
        startDate: { lte: end },
        endDate: { gte: start },
      },
    });
    return count > 0;
  }

  async createPeriod(ownerId: string, start: Date, end: Date, title: string) {
    if (end < start) {
      throw new BadRequestException('La fecha final no puede ser menor que la inicial');
    }

    const overlap = await this.hasOverlappingOpenPeriod(ownerId, start, end);
    if (overlap) {
      throw new BadRequestException('Ya existe una quincena abierta que se solapa con esas fechas');
    }

    return this.prisma.payrollPeriod.create({
      data: {
        ownerId,
        title: title.trim(),
        startDate: start,
        endDate: end,
        status: PayrollPeriodStatus.OPEN,
      },
    });
  }

  async ensureCurrentOpenPeriod(ownerId: string) {
    const now = new Date();
    const expectedStart = this.periodStartFor(now);
    const expectedEnd = this.periodEndFor(now);

    const openPeriods = await this.prisma.payrollPeriod.findMany({
      where: { ownerId, status: PayrollPeriodStatus.OPEN },
      orderBy: { startDate: 'desc' },
    });

    for (const period of openPeriods) {
      if (this.isSameDay(period.startDate, expectedStart) && this.isSameDay(period.endDate, expectedEnd)) {
        return period;
      }
    }

    if (openPeriods.length) {
      await this.prisma.payrollPeriod.updateMany({
        where: { ownerId, status: PayrollPeriodStatus.OPEN },
        data: { status: PayrollPeriodStatus.CLOSED },
      });
    }

    return this.prisma.payrollPeriod.create({
      data: {
        ownerId,
        title: this.periodTitle(now),
        startDate: expectedStart,
        endDate: expectedEnd,
        status: PayrollPeriodStatus.OPEN,
      },
    });
  }

  async closePeriod(ownerId: string, periodId: string) {
    const result = await this.prisma.payrollPeriod.updateMany({
      where: { ownerId, id: periodId },
      data: { status: PayrollPeriodStatus.CLOSED },
    });

    if (result.count === 0) {
      throw new NotFoundException('Quincena no encontrada');
    }
  }

  async createNextOpenPeriod(ownerId: string, closedPeriodId: string) {
    const closed = await this.getPeriodById(ownerId, closedPeriodId);
    if (!closed) {
      throw new NotFoundException('Quincena no encontrada');
    }

    const nextBase = new Date(closed.endDate.getTime() + 24 * 60 * 60 * 1000);
    const start = this.periodStartFor(nextBase);
    const end = this.periodEndFor(nextBase);
    const title = this.periodTitle(nextBase);

    const existing = await this.prisma.payrollPeriod.findFirst({
      where: {
        ownerId,
        status: PayrollPeriodStatus.OPEN,
        startDate: start,
        endDate: end,
      },
    });

    if (existing) {
      return existing;
    }

    return this.prisma.payrollPeriod.create({
      data: {
        ownerId,
        title,
        startDate: start,
        endDate: end,
        status: PayrollPeriodStatus.OPEN,
      },
    });
  }

  async listEmployees(ownerId: string, activeOnly = true) {
    return this.prisma.payrollEmployee.findMany({
      where: {
        ownerId,
        ...(activeOnly ? { activo: true } : {}),
      },
      orderBy: { nombre: 'asc' },
    });
  }

  async getEmployeeById(ownerId: string, employeeId: string) {
    return this.prisma.payrollEmployee.findFirst({
      where: { ownerId, id: employeeId },
    });
  }

  async upsertEmployee(ownerId: string, dto: UpsertPayrollEmployeeDto) {
    const nombre = dto.nombre.trim();
    if (!nombre) {
      throw new BadRequestException('El nombre del empleado es obligatorio');
    }

    const payload = {
      ownerId,
      nombre,
      telefono: dto.telefono?.trim() ? dto.telefono.trim() : null,
      puesto: dto.puesto?.trim() ? dto.puesto.trim() : null,
      cuotaMinima: new Prisma.Decimal(dto.cuotaMinima ?? 0),
      seguroLeyMonto: new Prisma.Decimal(dto.seguroLeyMonto ?? 0),
      activo: dto.activo ?? true,
    };

    if (dto.id) {
      const existing = await this.prisma.payrollEmployee.findFirst({
        where: { ownerId, id: dto.id },
        select: { id: true },
      });

      if (existing) {
        return this.prisma.payrollEmployee.update({
          where: { id: dto.id },
          data: payload,
        });
      }

      const userExists = await this.prisma.user.findUnique({
        where: { id: dto.id },
        select: { id: true },
      });

      if (!userExists) {
        throw new BadRequestException('El usuario seleccionado no existe');
      }

      return this.prisma.payrollEmployee.create({
        data: {
          id: dto.id,
          ...payload,
        },
      });
    }

    return this.prisma.payrollEmployee.create({ data: payload });
  }

  async getEmployeeConfig(ownerId: string, periodId: string, employeeId: string) {
    return this.prisma.payrollEmployeeConfig.findFirst({
      where: { ownerId, periodId, employeeId },
    });
  }

  async upsertEmployeeConfig(ownerId: string, dto: UpsertPayrollConfigDto) {
    return this.prisma.payrollEmployeeConfig.upsert({
      where: {
        ownerId_periodId_employeeId: {
          ownerId,
          periodId: dto.periodId,
          employeeId: dto.employeeId,
        },
      },
      create: {
        ownerId,
        periodId: dto.periodId,
        employeeId: dto.employeeId,
        baseSalary: new Prisma.Decimal(dto.baseSalary),
        includeCommissions: dto.includeCommissions,
        notes: dto.notes?.trim() ? dto.notes.trim() : null,
      },
      update: {
        baseSalary: new Prisma.Decimal(dto.baseSalary),
        includeCommissions: dto.includeCommissions,
        notes: dto.notes?.trim() ? dto.notes.trim() : null,
      },
    });
  }

  async listEntries(ownerId: string, periodId: string, employeeId: string) {
    return this.prisma.payrollEntry.findMany({
      where: { ownerId, periodId, employeeId },
      orderBy: [{ date: 'desc' }, { createdAt: 'desc' }],
    });
  }

  async addEntry(ownerId: string, dto: AddPayrollEntryDto) {
    return this.prisma.payrollEntry.create({
      data: {
        ownerId,
        periodId: dto.periodId,
        employeeId: dto.employeeId,
        date: new Date(dto.date),
        type: dto.type,
        concept: dto.concept.trim(),
        amount: new Prisma.Decimal(dto.amount),
        cantidad: dto.cantidad == null ? null : new Prisma.Decimal(dto.cantidad),
      },
    });
  }

  async deleteEntry(ownerId: string, entryId: string) {
    const result = await this.prisma.payrollEntry.deleteMany({ where: { ownerId, id: entryId } });
    if (result.count === 0) {
      throw new NotFoundException('Movimiento no encontrado');
    }
  }

  async computeTotals(ownerId: string, periodId: string, employeeId: string) {
    const [employee, config, entries] = await Promise.all([
      this.getEmployeeById(ownerId, employeeId),
      this.getEmployeeConfig(ownerId, periodId, employeeId),
      this.listEntries(ownerId, periodId, employeeId),
    ]);

    const period = await this.getPeriodById(ownerId, periodId);

    const base = this.toNumber(config?.baseSalary);
    let manualServiceCommissions = 0;
    let manualSalesCommissions = 0;
    let bonuses = 0;
    let otherAdditions = 0;
    let absences = 0;
    let late = 0;
    let advances = 0;
    let otherDeductions = 0;

    for (const entry of entries) {
      const amount = this.toNumber(entry.amount);
      switch (entry.type) {
        case PayrollEntryType.COMISION_SERVICIO:
          if (amount >= 0) manualServiceCommissions += amount;
          break;
        case PayrollEntryType.COMISION_VENTAS:
          if (amount >= 0) manualSalesCommissions += amount;
          break;
        case PayrollEntryType.BONIFICACION:
        case PayrollEntryType.PAGO_COMBUSTIBLE:
          if (amount >= 0) bonuses += amount;
          break;
        case PayrollEntryType.AUSENCIA:
          absences += Math.abs(amount);
          break;
        case PayrollEntryType.TARDE:
          late += Math.abs(amount);
          break;
        case PayrollEntryType.ADELANTO:
          advances += Math.abs(amount);
          break;
        case PayrollEntryType.DESCUENTO:
          otherDeductions += Math.abs(amount);
          break;
        case PayrollEntryType.OTRO:
          if (amount >= 0) {
            otherAdditions += amount;
          } else {
            otherDeductions += Math.abs(amount);
          }
          break;
      }
    }

    const hasLinkedSalesUser = Boolean(await this.resolveSalesUserIdForEmployee(ownerId, employee));
    const automaticSales = await this.computeAutomaticSalesCommissionForEmployee({
      ownerId,
      employee,
      includeCommissions: config?.includeCommissions ?? true,
      periodStart: period?.startDate,
      periodEnd: period?.endDate,
    });

    const commissions =
      automaticSales.usedAutomatic
        ? automaticSales.commissionAmount
        : manualSalesCommissions;

    const seguroLey = Math.max(
      0,
      this.toNumber(
        (employee as { seguroLeyMonto?: Prisma.Decimal | number | string | null } | null)
          ?.seguroLeyMonto,
      ),
    );
    const additions = commissions + manualServiceCommissions + bonuses + otherAdditions;
    const deductions = absences + late + advances + otherDeductions + seguroLey;
    const total = base + additions - deductions;

    return {
      baseSalary: base,
      commissions,
      serviceCommissions: manualServiceCommissions,
      bonuses,
      otherAdditions,
      absences,
      late,
      advances,
      otherDeductions,
      seguroLey,
      salesCommissionAuto: automaticSales.commissionAmount,
      salesAmountThisPeriod: automaticSales.salesAmount,
      salesGoal: automaticSales.goal,
      salesGoalReached: automaticSales.goalReached,
      salesCommissionSource: automaticSales.usedAutomatic
        ? 'automatic'
        : hasLinkedSalesUser
          ? 'automatic_disabled'
          : 'manual',
      additions,
      deductions,
      total,
      employeeExists: Boolean(employee),
    };
  }

  async computePeriodTotalAllEmployees(ownerId: string, periodId: string) {
    const employees = await this.listEmployees(ownerId, true);
    let total = 0;
    for (const employee of employees) {
      const t = await this.computeTotals(ownerId, periodId, employee.id);
      total += t.total;
    }
    return total;
  }

  async listPayrollHistoryByEmployee(ownerId: string, employeeId: string) {
    const periods = await this.listPeriods(ownerId);
    const employee = await this.getEmployeeById(ownerId, employeeId);
    const history: Array<Record<string, unknown>> = [];

    for (const period of periods) {
      const [entries, config] = await Promise.all([
        this.listEntries(ownerId, period.id, employeeId),
        this.getEmployeeConfig(ownerId, period.id, employeeId),
      ]);

      const automaticSales = await this.computeAutomaticSalesCommissionForEmployee({
        ownerId,
        employee,
        includeCommissions: config?.includeCommissions ?? true,
        periodStart: period.startDate,
        periodEnd: period.endDate,
      });

      const hasData =
        Boolean(config) ||
        entries.length > 0 ||
        automaticSales.salesAmount > 0 ||
        automaticSales.commissionAmount > 0;
      if (!hasData) continue;

      const baseSalary = this.toNumber(config?.baseSalary);
      const seguroLey = Math.max(
        0,
        this.toNumber(
          (employee as { seguroLeyMonto?: Prisma.Decimal | number | string | null } | null)
            ?.seguroLeyMonto,
        ),
      );
          let manualServiceCommissions = 0;
          let manualSalesCommissions = 0;
      let overtimeAmount = 0;
      let bonusesAmount = 0;
      let deductionsAmount = 0;
      let benefitsAmount = 0;

      for (const entry of entries) {
        const amount = this.toNumber(entry.amount);
        switch (entry.type) {
          case PayrollEntryType.COMISION_SERVICIO:
            if (amount >= 0) manualServiceCommissions += amount;
            break;
          case PayrollEntryType.COMISION_VENTAS:
            if (amount >= 0) manualSalesCommissions += amount;
            break;
          case PayrollEntryType.BONIFICACION:
          case PayrollEntryType.PAGO_COMBUSTIBLE:
            bonusesAmount += amount;
            break;
          case PayrollEntryType.AUSENCIA:
          case PayrollEntryType.TARDE:
          case PayrollEntryType.ADELANTO:
          case PayrollEntryType.DESCUENTO:
            deductionsAmount += Math.abs(amount);
            break;
          case PayrollEntryType.OTRO:
            if (amount >= 0) {
              benefitsAmount += amount;
            } else {
              deductionsAmount += Math.abs(amount);
            }
            break;
        }
      }

      const commissionFromSales =
        automaticSales.usedAutomatic
          ? automaticSales.commissionAmount
          : manualSalesCommissions;

      benefitsAmount += manualServiceCommissions;

      const additions = commissionFromSales + overtimeAmount + bonusesAmount + benefitsAmount;
      const grossTotal = baseSalary + additions;
      const totalDeductions = deductionsAmount + seguroLey;
      const netTotal = grossTotal - totalDeductions;

      history.push({
        entry_id: entries.length > 0 ? entries[0].id : `period_${period.id}`,
        employee_name: employee?.nombre ?? '',
        period_id: period.id,
        period_title: period.title,
        period_start: period.startDate.toISOString(),
        period_end: period.endDate.toISOString(),
        period_status: period.status,
        base_salary: baseSalary,
        commission_from_sales: commissionFromSales,
        overtime_amount: overtimeAmount,
        bonuses_amount: bonusesAmount,
        deductions_amount: totalDeductions,
        benefits_amount: benefitsAmount,
        gross_total: grossTotal,
        net_total: netTotal,
        seguro_ley_monto: seguroLey,
        sales_commission_auto: automaticSales.commissionAmount,
        sales_amount_this_period: automaticSales.salesAmount,
        sales_goal: automaticSales.goal,
        sales_goal_reached: automaticSales.goalReached,
      });
    }

    history.sort((a, b) => {
      const right = new Date((b['period_end'] ?? '').toString()).getTime();
      const left = new Date((a['period_end'] ?? '').toString()).getTime();
      return right - left;
    });

    return history;
  }

  async listMyPayrollHistory(ownerId: string, userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, nombreCompleto: true, telefono: true },
    });

    if (!user) {
      return [] as Array<Record<string, unknown>>;
    }

    const direct = await this.prisma.payrollEmployee.findMany({
      where: { ownerId, id: user.id },
      select: { id: true },
    });

    const fallback = await this.prisma.payrollEmployee.findMany({
      where: {
        ownerId,
        nombre: user.nombreCompleto,
        ...(user.telefono.trim().length > 0 ? { telefono: user.telefono } : {}),
      },
      select: { id: true },
    });

    const employeeIds = new Set<string>([user.id]);
    for (const item of direct) employeeIds.add(item.id);
    for (const item of fallback) employeeIds.add(item.id);

    const allHistory: Array<Record<string, unknown>> = [];
    for (const employeeId of employeeIds) {
      const rows = await this.listPayrollHistoryByEmployee(ownerId, employeeId);
      allHistory.push(...rows);
    }

    const unique = new Map<string, Record<string, unknown>>();
    for (const row of allHistory) {
      const key = (row['entry_id'] ?? '').toString();
      if (!key) continue;
      if (!unique.has(key)) unique.set(key, row);
    }

    const result = [...unique.values()];
    result.sort((a, b) => {
      const right = new Date((b['period_end'] ?? '').toString()).getTime();
      const left = new Date((a['period_end'] ?? '').toString()).getTime();
      return right - left;
    });

    return result;
  }

  async getCuotaMinimaForUser(ownerId: string, userId: string) {
    const byId = await this.prisma.payrollEmployee.findFirst({
      where: { ownerId, id: userId, activo: true },
      select: { cuotaMinima: true },
    });

    if (byId) {
      return this.toNumber(byId.cuotaMinima);
    }

    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { nombreCompleto: true, telefono: true },
    });

    if (!user) {
      return 0;
    }

    const legacyMatches = await this.prisma.payrollEmployee.findMany({
      where: {
        ownerId,
        activo: true,
        nombre: user.nombreCompleto,
        ...(user.telefono.trim().length > 0 ? { telefono: user.telefono } : {}),
      },
      select: { cuotaMinima: true },
      take: 2,
    });

    if (legacyMatches.length == 1) {
      return this.toNumber(legacyMatches[0].cuotaMinima);
    }

    return 0;
  }

  private async computeAutomaticSalesCommissionForEmployee(params: {
    ownerId: string;
    employee: {
      id: string;
      nombre: string;
      telefono: string | null;
      cuotaMinima: Prisma.Decimal | number | string | null;
    } | null;
    includeCommissions: boolean;
    periodStart?: Date;
    periodEnd?: Date;
  }) {
    const { ownerId, employee, includeCommissions, periodStart, periodEnd } = params;

    const goal = Math.max(0, this.toNumber(employee?.cuotaMinima));

    if (!includeCommissions || !periodStart || !periodEnd || !employee) {
      return {
        usedAutomatic: false,
        salesAmount: 0,
        commissionAmount: 0,
        goal,
        goalReached: false,
      };
    }

    const salesUserId = await this.resolveSalesUserIdForEmployee(ownerId, employee);
    if (!salesUserId) {
      return {
        usedAutomatic: false,
        salesAmount: 0,
        commissionAmount: 0,
        goal,
        goalReached: false,
      };
    }

    const start = new Date(periodStart.getFullYear(), periodStart.getMonth(), periodStart.getDate(), 0, 0, 0, 0);
    const endExclusive = new Date(periodEnd.getFullYear(), periodEnd.getMonth(), periodEnd.getDate() + 1, 0, 0, 0, 0);

    const aggregate = await this.prisma.sale.aggregate({
      where: {
        userId: salesUserId,
        isDeleted: false,
        saleDate: {
          gte: start,
          lt: endExclusive,
        },
      },
      _sum: {
        totalProfit: true,
        commissionAmount: true,
      },
    });

    const salesAmount = this.toNumber(aggregate._sum.totalProfit);
    const totalSalesCommission = this.toNumber(aggregate._sum.commissionAmount);
    const goalReached = goal <= 0 ? salesAmount > 0 : salesAmount >= goal;

    return {
      usedAutomatic: true,
      salesAmount,
      commissionAmount: goalReached ? totalSalesCommission : 0,
      goal,
      goalReached,
    };
  }

  private async resolveSalesUserIdForEmployee(
    ownerId: string,
    employee: { id: string; nombre: string; telefono: string | null } | null,
  ) {
    if (!employee) return null;

    const userById = await this.prisma.user.findUnique({
      where: { id: employee.id },
      select: { id: true },
    });
    if (userById) return userById.id;

    const trimmedName = employee.nombre.trim();
    if (!trimmedName) return null;

    const phone = (employee.telefono ?? '').trim();
    const users = await this.prisma.user.findMany({
      where: {
        nombreCompleto: trimmedName,
        ...(phone.length > 0 ? { telefono: phone } : {}),
      },
      select: { id: true },
      take: 2,
    });

    if (users.length === 1) return users[0].id;

    const payrollUsers = await this.prisma.payrollEmployee.findMany({
      where: {
        ownerId,
        nombre: trimmedName,
        ...(phone.length > 0 ? { telefono: phone } : {}),
      },
      select: { id: true },
      take: 2,
    });

    if (payrollUsers.length === 1) {
      const userByPayrollId = await this.prisma.user.findUnique({
        where: { id: payrollUsers[0].id },
        select: { id: true },
      });
      return userByPayrollId?.id ?? null;
    }

    return null;
  }

  private toNumber(value: Prisma.Decimal | number | string | null | undefined) {
    if (value == null) return 0;
    if (typeof value === 'number') return value;
    if (typeof value === 'string') {
      const parsed = Number(value);
      return Number.isFinite(parsed) ? parsed : 0;
    }
    return Number(value.toString());
  }

  private dateWithClampedDay(year: number, month: number, day: number) {
    const lastDay = new Date(year, month, 0).getDate();
    const safeDay = day > lastDay ? lastDay : day;
    return new Date(year, month - 1, safeDay);
  }

  private periodStartFor(date: Date) {
    const day = date.getDate();
    const year = date.getFullYear();
    const month = date.getMonth() + 1;

    if (day >= 15 && day <= 29) return new Date(year, month - 1, 15);
    if (day >= 30) return this.dateWithClampedDay(year, month, 30);

    const prev = new Date(year, month - 2, 1);
    return this.dateWithClampedDay(prev.getFullYear(), prev.getMonth() + 1, 30);
  }

  private periodEndFor(date: Date) {
    const day = date.getDate();
    const year = date.getFullYear();
    const month = date.getMonth() + 1;

    if (day >= 15 && day <= 29) return this.dateWithClampedDay(year, month, 29);
    if (day >= 30) return new Date(year, month, 14);
    return new Date(year, month - 1, 14);
  }

  private periodTitle(date: Date) {
    const start = this.periodStartFor(date);
    const end = this.periodEndFor(date);
    return this.periodTitleFromRange(start, end);
  }

  private periodTitleFromRange(start: Date, end: Date) {
    const sDay = start.getDate().toString().padStart(2, '0');
    const eDay = end.getDate().toString().padStart(2, '0');
    const month = (end.getMonth() + 1).toString().padStart(2, '0');
    const year = end.getFullYear().toString();
    const quincenaNumber = end.getDate() <= 14 ? 1 : 2;
    return `Quincena ${quincenaNumber} · ${sDay}-${eDay}/${month}/${year}`;
  }

  private isSameDay(left: Date, right: Date) {
    return (
      left.getFullYear() === right.getFullYear() &&
      left.getMonth() === right.getMonth() &&
      left.getDate() === right.getDate()
    );
  }
}
