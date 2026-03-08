import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import {
  PagoCombustibleTecnicoEstado,
  Prisma,
  Role,
  SalidaTecnicaEstado,
  ServiceStatus,
  ServiceUpdateType,
} from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { OperationsService } from '../operations/operations-main.service';
import { haversineKm, round2 } from './geo.util';

@Injectable()
export class SalidasTecnicasService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly operations: OperationsService,
  ) {}

  async listVehiculosForTecnico(tecnicoId: string) {
    const items = await this.prisma.vehiculo.findMany({
      where: {
        activo: true,
        OR: [{ esEmpresa: true }, { tecnicoIdPropietario: tecnicoId }],
      },
      orderBy: [{ esEmpresa: 'desc' }, { nombre: 'asc' }],
    });
    return { items };
  }

  async createVehiculoPropio(
    tecnicoId: string,
    dto: { nombre: string; tipo: string; placa?: string; combustibleTipo: string; rendimientoKmLitro: number },
  ) {
    const created = await this.prisma.vehiculo.create({
      data: {
        nombre: dto.nombre.trim(),
        tipo: dto.tipo.trim(),
        placa: dto.placa?.trim() || null,
        combustibleTipo: dto.combustibleTipo.trim(),
        rendimientoKmLitro: new Prisma.Decimal(dto.rendimientoKmLitro),
        esEmpresa: false,
        tecnicoIdPropietario: tecnicoId,
        activo: true,
      },
    });
    return created;
  }

  async updateVehiculoPropio(
    tecnicoId: string,
    vehiculoId: string,
    dto: { nombre?: string; tipo?: string; placa?: string; combustibleTipo?: string; rendimientoKmLitro?: number; activo?: boolean },
  ) {
    const vehiculo = await this.prisma.vehiculo.findUnique({ where: { id: vehiculoId } });
    if (!vehiculo || vehiculo.esEmpresa) throw new NotFoundException('Vehículo no encontrado');
    if (vehiculo.tecnicoIdPropietario !== tecnicoId) throw new ForbiddenException('No autorizado');

    const data: Prisma.VehiculoUpdateInput = {
      ...(dto.nombre !== undefined ? { nombre: dto.nombre.trim() } : {}),
      ...(dto.tipo !== undefined ? { tipo: dto.tipo.trim() } : {}),
      ...(dto.placa !== undefined ? { placa: dto.placa?.trim() || null } : {}),
      ...(dto.combustibleTipo !== undefined ? { combustibleTipo: dto.combustibleTipo.trim() } : {}),
      ...(dto.rendimientoKmLitro !== undefined
        ? { rendimientoKmLitro: new Prisma.Decimal(dto.rendimientoKmLitro) }
        : {}),
      ...(dto.activo !== undefined ? { activo: dto.activo } : {}),
    };

    if (Object.keys(data).length === 0) {
      throw new BadRequestException('No hay cambios para guardar');
    }

    return this.prisma.vehiculo.update({ where: { id: vehiculoId }, data });
  }

  async listMisSalidas(
    tecnicoId: string,
    query?: { from?: string; to?: string; estado?: string },
  ) {
    const where: Prisma.SalidaTecnicaWhereInput = {
      tecnicoId,
      ...(query?.estado ? { estado: this.parseSalidaEstado(query.estado) } : {}),
      ...this.dateRangeWhere(query?.from, query?.to),
    };

    const items = await this.prisma.salidaTecnica.findMany({
      where,
      include: {
        vehiculo: true,
        servicio: {
          select: {
            id: true,
            title: true,
            customerId: true,
            status: true,
            orderState: true,
            scheduledStart: true,
          },
        },
      },
      orderBy: { createdAt: 'desc' },
      take: 200,
    });

    return { items };
  }

  async getSalidaAbierta(tecnicoId: string) {
    const salida = await this.prisma.salidaTecnica.findFirst({
      where: {
        tecnicoId,
        estado: { in: [SalidaTecnicaEstado.INICIADA, SalidaTecnicaEstado.LLEGADA] },
      },
      include: {
        vehiculo: true,
        servicio: { select: { id: true, title: true, customerId: true, status: true, orderState: true } },
      },
      orderBy: { createdAt: 'desc' },
    });
    return { salida };
  }

  async iniciarSalidaTecnica(params: {
    tecnicoId: string;
    servicioId: string;
    vehiculoId: string;
    esVehiculoPropio: boolean;
    latSalida: number;
    lngSalida: number;
    observacion?: string;
  }) {
    const tecnicoId = params.tecnicoId;

    const alreadyOpen = await this.prisma.salidaTecnica.findFirst({
      where: {
        tecnicoId,
        estado: { in: [SalidaTecnicaEstado.INICIADA, SalidaTecnicaEstado.LLEGADA] },
      },
      select: { id: true },
    });
    if (alreadyOpen) throw new BadRequestException('Ya tienes una salida abierta');

    const [vehiculo, service] = await Promise.all([
      this.prisma.vehiculo.findUnique({ where: { id: params.vehiculoId } }),
      this.prisma.service.findFirst({
        where: { id: params.servicioId, isDeleted: false },
        include: { assignments: true },
      }),
    ]);

    if (!service) throw new NotFoundException('Servicio no encontrado');

    const assignedIds = service.assignments.map((a: { userId: string }) => a.userId);
    if (!assignedIds.includes(tecnicoId)) {
      throw new ForbiddenException('Servicio no asignado a este técnico');
    }

    if (!vehiculo || !vehiculo.activo) throw new BadRequestException('Vehículo inválido');

    if (params.esVehiculoPropio) {
      if (vehiculo.esEmpresa) throw new BadRequestException('Vehículo inválido: es de empresa');
      if (vehiculo.tecnicoIdPropietario !== tecnicoId) {
        throw new ForbiddenException('No puedes usar el vehículo propio de otro técnico');
      }
      const rendimiento = this.toNumber(vehiculo.rendimientoKmLitro);
      if (!rendimiento || rendimiento <= 0) {
        throw new BadRequestException('Rendimiento km/l requerido para vehículo propio');
      }
    } else {
      if (!vehiculo.esEmpresa) throw new BadRequestException('Debe seleccionar un vehículo de empresa');
    }

    const generaPagoCombustible = params.esVehiculoPropio;
    const precio = generaPagoCombustible
      ? await this.findPrecioCombustibleOrThrow(vehiculo.combustibleTipo)
      : null;

    const now = new Date();

    try {
      const salida = await this.prisma.$transaction(async (tx) => {
        const created = await tx.salidaTecnica.create({
          data: {
            servicioId: params.servicioId,
            tecnicoId,
            vehiculoId: params.vehiculoId,
            esVehiculoPropio: params.esVehiculoPropio,
            generaPagoCombustible,
            fecha: now,
            horaSalida: now,
            latSalida: params.latSalida,
            lngSalida: params.lngSalida,
            precioCombustibleLitro: precio ? precio.precioPorLitro : null,
            montoCombustible: new Prisma.Decimal(0),
            estado: SalidaTecnicaEstado.INICIADA,
            observacion: params.observacion?.trim() || null,
          },
          include: { vehiculo: true },
        });

        await tx.serviceUpdate.create({
          data: {
            serviceId: params.servicioId,
            changedByUserId: tecnicoId,
            type: ServiceUpdateType.NOTE,
            newValue: { salidaTecnicaId: created.id, trip: 'en_camino' } as Prisma.InputJsonValue,
            message: 'En camino (salida técnica iniciada)',
          },
        });

        return created;
      });

      // Mejor esfuerzo: avanzar Operaciones a IN_PROGRESS si aplica
      try {
        if (service.status === ServiceStatus.SCHEDULED) {
          await this.operations.changeStatus(
            { id: tecnicoId, role: Role.TECNICO },
            params.servicioId,
            { status: 'in_progress', message: 'Salida técnica iniciada' } as any,
          );
        }
      } catch {
        // ignore
      }

      return salida;
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        throw new BadRequestException('Ya tienes una salida abierta');
      }
      throw error;
    }
  }

  async marcarLlegada(params: {
    tecnicoId: string;
    salidaId: string;
    latLlegada: number;
    lngLlegada: number;
    observacion?: string;
  }) {
    const salida = await this.prisma.salidaTecnica.findUnique({ where: { id: params.salidaId } });
    if (!salida) throw new NotFoundException('Salida no encontrada');
    if (salida.tecnicoId !== params.tecnicoId) throw new ForbiddenException('No autorizado');
    if (salida.estado !== SalidaTecnicaEstado.INICIADA) {
      throw new BadRequestException('La salida no está en estado INICIADA');
    }

    const now = new Date();

    return this.prisma.$transaction(async (tx) => {
      const row = await tx.salidaTecnica.update({
        where: { id: params.salidaId },
        data: {
          horaLlegada: now,
          latLlegada: params.latLlegada,
          lngLlegada: params.lngLlegada,
          estado: SalidaTecnicaEstado.LLEGADA,
          ...(params.observacion?.trim() ? { observacion: params.observacion.trim() } : {}),
        },
      });

      await tx.serviceUpdate.create({
        data: {
          serviceId: salida.servicioId,
          changedByUserId: params.tecnicoId,
          type: ServiceUpdateType.NOTE,
          newValue: { salidaTecnicaId: salida.id, trip: 'en_sitio' } as Prisma.InputJsonValue,
          message: 'En sitio (salida técnica: llegada)',
        },
      });

      return row;
    });
  }

  async finalizarSalida(params: {
    tecnicoId: string;
    salidaId: string;
    latFinal: number;
    lngFinal: number;
    observacion?: string;
  }) {
    const salida = await this.prisma.salidaTecnica.findUnique({
      where: { id: params.salidaId },
      include: { vehiculo: true },
    });

    if (!salida) throw new NotFoundException('Salida no encontrada');
    if (salida.tecnicoId !== params.tecnicoId) throw new ForbiddenException('No autorizado');
    if (salida.estado !== SalidaTecnicaEstado.LLEGADA && salida.estado !== SalidaTecnicaEstado.INICIADA) {
      throw new BadRequestException('La salida no está abierta');
    }

    const now = new Date();

    const segments: number[] = [];
    if (salida.latLlegada != null && salida.lngLlegada != null) {
      segments.push(haversineKm(salida.latSalida, salida.lngSalida, salida.latLlegada, salida.lngLlegada));
      segments.push(haversineKm(salida.latLlegada, salida.lngLlegada, params.latFinal, params.lngFinal));
    } else {
      segments.push(haversineKm(salida.latSalida, salida.lngSalida, params.latFinal, params.lngFinal));
    }

    const km = round2(segments.reduce((a, b) => a + b, 0));

    let litros = 0;
    let monto = 0;

    if (salida.generaPagoCombustible) {
      const rendimiento = this.toNumber(salida.vehiculo.rendimientoKmLitro);
      if (!rendimiento || rendimiento <= 0) {
        throw new BadRequestException('Rendimiento km/l inválido en vehículo');
      }
      const precio = this.toNumber(salida.precioCombustibleLitro);
      if (!precio || precio <= 0) {
        throw new BadRequestException('Precio de combustible no configurado');
      }

      litros = round2(km / rendimiento);
      monto = round2(litros * precio);
    }

    return this.prisma.$transaction(async (tx) => {
      const row = await tx.salidaTecnica.update({
        where: { id: salida.id },
        data: {
          horaFinal: now,
          latFinal: params.latFinal,
          lngFinal: params.lngFinal,
          kmEstimados: new Prisma.Decimal(km),
          litrosEstimados: salida.generaPagoCombustible ? new Prisma.Decimal(litros) : null,
          montoCombustible: new Prisma.Decimal(monto),
          estado: SalidaTecnicaEstado.FINALIZADA,
          ...(params.observacion?.trim() ? { observacion: params.observacion.trim() } : {}),
        },
      });

      await tx.serviceUpdate.create({
        data: {
          serviceId: salida.servicioId,
          changedByUserId: params.tecnicoId,
          type: ServiceUpdateType.NOTE,
          newValue: { salidaTecnicaId: salida.id, trip: 'finalizada' } as Prisma.InputJsonValue,
          message: 'Salida técnica finalizada',
        },
      });

      return row;
    });
  }

  async adminListSalidas(query?: { from?: string; to?: string; estado?: string; tecnicoId?: string }) {
    const where: Prisma.SalidaTecnicaWhereInput = {
      ...(query?.tecnicoId ? { tecnicoId: query.tecnicoId } : {}),
      ...(query?.estado ? { estado: this.parseSalidaEstado(query.estado) } : {}),
      ...this.dateRangeWhere(query?.from, query?.to),
    };

    const items = await this.prisma.salidaTecnica.findMany({
      where,
      include: {
        tecnico: { select: { id: true, nombreCompleto: true } },
        vehiculo: true,
        servicio: { select: { id: true, title: true, customerId: true, status: true, orderState: true } },
        pagoCombustible: true,
      },
      orderBy: { createdAt: 'desc' },
      take: 500,
    });

    return { items };
  }

  async adminAprobarSalida(actorId: string, salidaId: string, observacion?: string) {
    const salida = await this.prisma.salidaTecnica.findUnique({ where: { id: salidaId } });
    if (!salida) throw new NotFoundException('Salida no encontrada');
    if (salida.estado !== SalidaTecnicaEstado.FINALIZADA) {
      throw new BadRequestException('Solo se puede aprobar una salida FINALIZADA');
    }

    return this.prisma.$transaction(async (tx) => {
      const row = await tx.salidaTecnica.update({
        where: { id: salidaId },
        data: {
          estado: SalidaTecnicaEstado.APROBADA,
          ...(observacion?.trim() ? { observacion: observacion.trim() } : {}),
        },
      });

      await tx.serviceUpdate.create({
        data: {
          serviceId: salida.servicioId,
          changedByUserId: actorId,
          type: ServiceUpdateType.NOTE,
          newValue: { salidaTecnicaId: salida.id, admin: 'aprobada' } as Prisma.InputJsonValue,
          message: 'Salida técnica aprobada',
        },
      });

      return row;
    });
  }

  async adminRechazarSalida(actorId: string, salidaId: string, observacion: string) {
    const salida = await this.prisma.salidaTecnica.findUnique({ where: { id: salidaId } });
    if (!salida) throw new NotFoundException('Salida no encontrada');
    if (salida.estado !== SalidaTecnicaEstado.FINALIZADA) {
      throw new BadRequestException('Solo se puede rechazar una salida FINALIZADA');
    }

    return this.prisma.$transaction(async (tx) => {
      const row = await tx.salidaTecnica.update({
        where: { id: salidaId },
        data: { estado: SalidaTecnicaEstado.RECHAZADA, observacion: observacion.trim() },
      });

      await tx.serviceUpdate.create({
        data: {
          serviceId: salida.servicioId,
          changedByUserId: actorId,
          type: ServiceUpdateType.NOTE,
          newValue: { salidaTecnicaId: salida.id, admin: 'rechazada' } as Prisma.InputJsonValue,
          message: 'Salida técnica rechazada',
        },
      });

      return row;
    });
  }

  async adminCrearPagoPeriodo(actorId: string, tecnicoId: string, fechaInicioRaw: string, fechaFinRaw: string) {
    const fechaInicio = new Date(fechaInicioRaw);
    const fechaFin = new Date(fechaFinRaw);
    if (Number.isNaN(fechaInicio.getTime()) || Number.isNaN(fechaFin.getTime()) || fechaFin < fechaInicio) {
      throw new BadRequestException('Rango de fechas inválido');
    }

    const tecnico = await this.prisma.user.findFirst({
      where: { id: tecnicoId, role: Role.TECNICO, blocked: false },
      select: { id: true },
    });
    if (!tecnico) throw new BadRequestException('Técnico inválido');

    return this.prisma.$transaction(async (tx) => {
      const salidas = await tx.salidaTecnica.findMany({
        where: {
          tecnicoId,
          estado: SalidaTecnicaEstado.APROBADA,
          generaPagoCombustible: true,
          pagoCombustibleId: null,
          fecha: { gte: fechaInicio, lte: fechaFin },
        },
        select: { id: true, montoCombustible: true },
      });

      const total = round2(
        salidas.reduce(
          (sum: number, s: { montoCombustible: unknown }) => sum + this.toNumber(s.montoCombustible),
          0,
        ),
      );

      const pago = await tx.pagoCombustibleTecnico.create({
        data: {
          tecnicoId,
          fechaInicio,
          fechaFin,
          totalMonto: new Prisma.Decimal(total),
          estado: PagoCombustibleTecnicoEstado.PENDIENTE,
        },
      });

      if (salidas.length > 0) {
        await tx.salidaTecnica.updateMany({
          where: { id: { in: salidas.map((s: { id: string }) => s.id) } },
          data: { pagoCombustibleId: pago.id },
        });
      }

      return { pago, countSalidas: salidas.length };
    });
  }

  async adminMarcarPagoPagado(pagoId: string, fechaPagoRaw?: string) {
    const pago = await this.prisma.pagoCombustibleTecnico.findUnique({ where: { id: pagoId } });
    if (!pago) throw new NotFoundException('Pago no encontrado');

    const fechaPago = fechaPagoRaw ? new Date(fechaPagoRaw) : new Date();
    if (Number.isNaN(fechaPago.getTime())) throw new BadRequestException('fechaPago inválida');

    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.pagoCombustibleTecnico.update({
        where: { id: pagoId },
        data: { estado: PagoCombustibleTecnicoEstado.PAGADO, fechaPago },
      });

      await tx.salidaTecnica.updateMany({
        where: { pagoCombustibleId: pagoId, estado: SalidaTecnicaEstado.APROBADA },
        data: { estado: SalidaTecnicaEstado.PAGADA },
      });

      return updated;
    });
  }

  async listMisPagosCombustible(tecnicoId: string) {
    const items = await this.prisma.pagoCombustibleTecnico.findMany({
      where: { tecnicoId },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
    return { items };
  }

  async listPagosAdmin(tecnicoId?: string) {
    const items = await this.prisma.pagoCombustibleTecnico.findMany({
      where: tecnicoId ? { tecnicoId } : {},
      include: { tecnico: { select: { id: true, nombreCompleto: true } } },
      orderBy: { createdAt: 'desc' },
      take: 200,
    });
    return { items };
  }

  private parseSalidaEstado(value: string): SalidaTecnicaEstado {
    const key = value.trim().toLowerCase();
    const map: Record<string, SalidaTecnicaEstado> = {
      iniciada: SalidaTecnicaEstado.INICIADA,
      llegada: SalidaTecnicaEstado.LLEGADA,
      finalizada: SalidaTecnicaEstado.FINALIZADA,
      aprobada: SalidaTecnicaEstado.APROBADA,
      rechazada: SalidaTecnicaEstado.RECHAZADA,
      pagada: SalidaTecnicaEstado.PAGADA,
    };
    const parsed = map[key];
    if (!parsed) throw new BadRequestException('Estado inválido');
    return parsed;
  }

  private dateRangeWhere(fromRaw?: string, toRaw?: string): Prisma.SalidaTecnicaWhereInput {
    const from = (fromRaw ?? '').trim();
    const to = (toRaw ?? '').trim();
    if (!from && !to) return {};

    const gte = from ? new Date(from) : null;
    const lte = to ? new Date(to) : null;

    if (gte && Number.isNaN(gte.getTime())) throw new BadRequestException('from inválido');
    if (lte && Number.isNaN(lte.getTime())) throw new BadRequestException('to inválido');

    return {
      fecha: {
        ...(gte ? { gte } : {}),
        ...(lte ? { lte } : {}),
      },
    };
  }

  private toNumber(value: unknown): number {
    if (value == null) return 0;
    if (typeof value === 'number') return value;
    if (typeof value === 'string') {
      const n = Number(value);
      return Number.isFinite(n) ? n : 0;
    }
    if (typeof value === 'object' && value !== null && 'toNumber' in (value as any)) {
      try {
        return (value as any).toNumber();
      } catch {
        return 0;
      }
    }
    return 0;
  }

  private async findPrecioCombustibleOrThrow(combustibleTipo: string) {
    const precio = await this.prisma.precioCombustible.findFirst({
      where: { combustibleTipo: combustibleTipo.trim(), activo: true },
      orderBy: [{ vigenciaDesde: 'desc' }, { createdAt: 'desc' }],
    });
    if (!precio) {
      throw new BadRequestException(`No hay precio de combustible activo para: ${combustibleTipo}`);
    }
    return precio;
  }
}
