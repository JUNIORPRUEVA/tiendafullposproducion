import { Body, Controller, Delete, Get, Param, Patch, Post, Query, Req, UseGuards } from '@nestjs/common';
import { PayrollPeriodStatus, Role } from '@prisma/client';
import { AuthGuard } from '@nestjs/passport';
import { Request } from 'express';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { CreatePayrollPeriodDto } from './dto/create-payroll-period.dto';
import { AddPayrollEntryDto, PayrollEntriesQueryDto } from './dto/payroll-entry.dto';
import { PayrollGoalQueryDto, PayrollTotalsQueryDto } from './dto/payroll-query.dto';
import { OverlapPeriodQueryDto } from './dto/overlap-period-query.dto';
import { UpsertPayrollConfigDto } from './dto/upsert-payroll-config.dto';
import { UpsertPayrollEmployeeDto } from './dto/upsert-payroll-employee.dto';
import { PayrollService } from './payroll.service';

type JwtUser = {
  id: string;
  role: Role;
};

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('payroll')
export class PayrollController {
  constructor(private readonly payroll: PayrollService) {}

  @Get('periods')
  @Roles(Role.ADMIN)
  async listPeriods(@Req() req: Request) {
    const ownerId = await this.ownerIdFrom(req);
    const periods = await this.payroll.listPeriods(ownerId);
    return periods.map((item) => this.mapPeriod(item));
  }

  @Get('periods/open-overlap')
  @Roles(Role.ADMIN)
  async hasOverlappingOpenPeriod(@Req() req: Request, @Query() query: OverlapPeriodQueryDto) {
    const ownerId = await this.ownerIdFrom(req);
    const overlaps = await this.payroll.hasOverlappingOpenPeriod(ownerId, new Date(query.start), new Date(query.end));
    return { overlaps };
  }

  @Get('periods/:id')
  @Roles(Role.ADMIN)
  async getPeriodById(@Req() req: Request, @Param('id') id: string) {
    const ownerId = await this.ownerIdFrom(req);
    const period = await this.payroll.getPeriodById(ownerId, id);
    return period ? this.mapPeriod(period) : null;
  }

  @Post('periods')
  @Roles(Role.ADMIN)
  async createPeriod(@Req() req: Request, @Body() dto: CreatePayrollPeriodDto) {
    const ownerId = await this.ownerIdFrom(req);
    const period = await this.payroll.createPeriod(ownerId, new Date(dto.start), new Date(dto.end), dto.title);
    return this.mapPeriod(period);
  }

  @Post('periods/ensure-current-open')
  @Roles(Role.ADMIN)
  async ensureCurrentOpenPeriod(@Req() req: Request) {
    const ownerId = await this.ownerIdFrom(req);
    const period = await this.payroll.ensureCurrentOpenPeriod(ownerId);
    return this.mapPeriod(period);
  }

  @Patch('periods/:id/close')
  @Roles(Role.ADMIN)
  async closePeriod(@Req() req: Request, @Param('id') id: string) {
    const ownerId = await this.ownerIdFrom(req);
    await this.payroll.closePeriod(ownerId, id);
    return { ok: true };
  }

  @Post('periods/:id/next-open')
  @Roles(Role.ADMIN)
  async createNextOpenPeriod(@Req() req: Request, @Param('id') id: string) {
    const ownerId = await this.ownerIdFrom(req);
    const period = await this.payroll.createNextOpenPeriod(ownerId, id);
    return this.mapPeriod(period);
  }

  @Get('periods/:id/total-all')
  @Roles(Role.ADMIN)
  async computePeriodTotalAllEmployees(@Req() req: Request, @Param('id') id: string) {
    const ownerId = await this.ownerIdFrom(req);
    const total = await this.payroll.computePeriodTotalAllEmployees(ownerId, id);
    return { total };
  }

  @Get('employees')
  @Roles(Role.ADMIN)
  async listEmployees(@Req() req: Request, @Query('activeOnly') activeOnly?: string) {
    const ownerId = await this.ownerIdFrom(req);
    const useActiveOnly = activeOnly == null ? true : activeOnly.toLowerCase() !== 'false';
    const employees = await this.payroll.listEmployees(ownerId, useActiveOnly);
    return employees.map((item) => this.mapEmployee(item));
  }

  @Get('employees/:id')
  @Roles(Role.ADMIN)
  async getEmployeeById(@Req() req: Request, @Param('id') id: string) {
    const ownerId = await this.ownerIdFrom(req);
    const employee = await this.payroll.getEmployeeById(ownerId, id);
    return employee ? this.mapEmployee(employee) : null;
  }

  @Post('employees/upsert')
  @Roles(Role.ADMIN)
  async upsertEmployee(@Req() req: Request, @Body() dto: UpsertPayrollEmployeeDto) {
    const ownerId = await this.ownerIdFrom(req);
    const employee = await this.payroll.upsertEmployee(ownerId, dto);
    return this.mapEmployee(employee);
  }

  @Get('config')
  @Roles(Role.ADMIN)
  async getEmployeeConfig(@Req() req: Request, @Query('periodId') periodId: string, @Query('employeeId') employeeId: string) {
    const ownerId = await this.ownerIdFrom(req);
    const config = await this.payroll.getEmployeeConfig(ownerId, periodId, employeeId);
    return config ? this.mapConfig(config) : null;
  }

  @Post('config/upsert')
  @Roles(Role.ADMIN)
  async upsertEmployeeConfig(@Req() req: Request, @Body() dto: UpsertPayrollConfigDto) {
    const ownerId = await this.ownerIdFrom(req);
    const config = await this.payroll.upsertEmployeeConfig(ownerId, dto);
    return this.mapConfig(config);
  }

  @Get('entries')
  @Roles(Role.ADMIN)
  async listEntries(@Req() req: Request, @Query() query: PayrollEntriesQueryDto) {
    const ownerId = await this.ownerIdFrom(req);
    const entries = await this.payroll.listEntries(ownerId, query.periodId, query.employeeId);
    return entries.map((item) => this.mapEntry(item));
  }

  @Post('entries')
  @Roles(Role.ADMIN)
  async addEntry(@Req() req: Request, @Body() dto: AddPayrollEntryDto) {
    const ownerId = await this.ownerIdFrom(req);
    const entry = await this.payroll.addEntry(ownerId, dto);
    return this.mapEntry(entry);
  }

  @Delete('entries/:id')
  @Roles(Role.ADMIN)
  async deleteEntry(@Req() req: Request, @Param('id') id: string) {
    const ownerId = await this.ownerIdFrom(req);
    await this.payroll.deleteEntry(ownerId, id);
    return { ok: true };
  }

  @Get('totals')
  @Roles(Role.ADMIN)
  async computeTotals(@Req() req: Request, @Query() query: PayrollTotalsQueryDto) {
    const ownerId = await this.ownerIdFrom(req);
    return this.payroll.computeTotals(ownerId, query.periodId, query.employeeId);
  }

  @Get('my-history')
  async listMyPayrollHistory(@Req() req: Request) {
    const ownerId = await this.ownerIdFrom(req);
    const user = req.user as JwtUser;
    return this.payroll.listPayrollHistoryByEmployee(ownerId, user.id);
  }

  @Get('my-goal')
  async getCuotaMinima(@Req() req: Request, @Query() query: PayrollGoalQueryDto) {
    const ownerId = await this.ownerIdFrom(req);
    const user = req.user as JwtUser;
    const userId = query.userId ?? user.id;
    const quota = await this.payroll.getCuotaMinimaForUser(ownerId, userId, query.userName ?? '');
    return { cuota_minima: quota };
  }

  private async ownerIdFrom(req: Request) {
    const user = req.user as JwtUser;
    return this.payroll.resolveCompanyOwnerId(user.id);
  }

  private mapEmployee(employee: {
    id: string;
    ownerId: string;
    nombre: string;
    telefono: string | null;
    puesto: string | null;
    cuotaMinima: unknown;
    seguroLeyMonto: unknown;
    activo: boolean;
    createdAt: Date;
    updatedAt: Date;
  }) {
    return {
      id: employee.id,
      owner_id: employee.ownerId,
      nombre: employee.nombre,
      telefono: employee.telefono,
      puesto: employee.puesto,
      cuota_minima: Number(employee.cuotaMinima ?? 0),
      seguro_ley_monto: Number(employee.seguroLeyMonto ?? 0),
      activo: employee.activo ? 1 : 0,
      created_at: employee.createdAt.toISOString(),
      updated_at: employee.updatedAt.toISOString(),
    };
  }

  private mapPeriod(period: {
    id: string;
    ownerId: string;
    title: string;
    startDate: Date;
    endDate: Date;
    status: PayrollPeriodStatus;
    createdAt: Date;
    updatedAt: Date;
  }) {
    return {
      id: period.id,
      owner_id: period.ownerId,
      title: period.title,
      start_date: period.startDate.toISOString(),
      end_date: period.endDate.toISOString(),
      status: period.status,
      created_at: period.createdAt.toISOString(),
      updated_at: period.updatedAt.toISOString(),
    };
  }

  private mapConfig(config: {
    id: string;
    ownerId: string;
    periodId: string;
    employeeId: string;
    baseSalary: unknown;
    includeCommissions: boolean;
    notes: string | null;
    createdAt: Date;
    updatedAt: Date;
  }) {
    return {
      id: config.id,
      owner_id: config.ownerId,
      period_id: config.periodId,
      employee_id: config.employeeId,
      base_salary: Number(config.baseSalary ?? 0),
      include_commissions: config.includeCommissions ? 1 : 0,
      notes: config.notes,
      created_at: config.createdAt.toISOString(),
      updated_at: config.updatedAt.toISOString(),
    };
  }

  private mapEntry(entry: {
    id: string;
    ownerId: string;
    periodId: string;
    employeeId: string;
    date: Date;
    type: string;
    concept: string;
    amount: unknown;
    cantidad: unknown;
    createdAt: Date;
  }) {
    return {
      id: entry.id,
      owner_id: entry.ownerId,
      period_id: entry.periodId,
      employee_id: entry.employeeId,
      date: entry.date.toISOString(),
      type: entry.type,
      concept: entry.concept,
      amount: Number(entry.amount ?? 0),
      cantidad: entry.cantidad == null ? null : Number(entry.cantidad),
      created_at: entry.createdAt.toISOString(),
    };
  }
}
