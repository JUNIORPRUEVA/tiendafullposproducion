class TechVehicle {
  final String id;
  final String nombre;
  final String tipo;
  final String? marca;
  final String? modelo;
  final String? placa;
  final String combustibleTipo;
  final double? rendimientoKmLitro;
  final double? capacidadTanqueLitros;
  final bool esEmpresa;
  final bool activo;

  const TechVehicle({
    required this.id,
    required this.nombre,
    required this.tipo,
    this.marca,
    this.modelo,
    this.placa,
    required this.combustibleTipo,
    this.rendimientoKmLitro,
    this.capacidadTanqueLitros,
    required this.esEmpresa,
    required this.activo,
  });

  String get displayName {
    final parts = <String>[nombre.trim()];
    final brand = [
      marca?.trim(),
      modelo?.trim(),
    ].whereType<String>().where((value) => value.isNotEmpty).join(' ');
    if (brand.isNotEmpty) parts.add(brand);
    return parts.join(' · ');
  }

  factory TechVehicle.fromJson(Map<String, dynamic> json) {
    double? parseNum(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString());
    }

    return TechVehicle(
      id: (json['id'] ?? '').toString(),
      nombre: (json['nombre'] ?? '').toString(),
      tipo: (json['tipo'] ?? '').toString(),
      marca: json['marca']?.toString(),
      modelo: json['modelo']?.toString(),
      placa: json['placa']?.toString(),
      combustibleTipo: (json['combustibleTipo'] ?? '').toString(),
      rendimientoKmLitro: parseNum(json['rendimientoKmLitro']),
      capacidadTanqueLitros: parseNum(json['capacidadTanqueLitros']),
      esEmpresa: json['esEmpresa'] == true,
      activo: json['activo'] != false,
    );
  }
}

class TechServiceSummary {
  final String id;
  final String title;
  final String status;
  final String orderState;

  const TechServiceSummary({
    required this.id,
    required this.title,
    required this.status,
    required this.orderState,
  });
}

class TechUserSummary {
  final String id;
  final String nombreCompleto;

  const TechUserSummary({required this.id, required this.nombreCompleto});

  factory TechUserSummary.fromJson(Map<String, dynamic> json) {
    return TechUserSummary(
      id: (json['id'] ?? '').toString(),
      nombreCompleto: (json['nombreCompleto'] ?? json['nombre'] ?? 'Técnico')
          .toString(),
    );
  }
}

class TechFuelPayment {
  final String id;
  final String tecnicoId;
  final DateTime? fechaInicio;
  final DateTime? fechaFin;
  final DateTime? fechaPago;
  final double totalMonto;
  final String estado;
  final TechUserSummary? tecnico;
  final String? payrollEntryId;
  final String? payrollPeriodId;

  const TechFuelPayment({
    required this.id,
    required this.tecnicoId,
    this.fechaInicio,
    this.fechaFin,
    this.fechaPago,
    required this.totalMonto,
    required this.estado,
    this.tecnico,
    this.payrollEntryId,
    this.payrollPeriodId,
  });

  bool get isPending => estado.toUpperCase() == 'PENDIENTE';
  bool get isPaid => estado.toUpperCase() == 'PAGADO';

  factory TechFuelPayment.fromJson(Map<String, dynamic> json) {
    double parseNum(dynamic value) {
      if (value == null) return 0;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString()) ?? 0;
    }

    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      return DateTime.tryParse(value.toString());
    }

    Map<String, dynamic>? asMap(dynamic value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return value.cast<String, dynamic>();
      return null;
    }

    final tecnicoJson = asMap(json['tecnico']);
    final payrollEntryJson = asMap(json['payrollEntry']);

    return TechFuelPayment(
      id: (json['id'] ?? '').toString(),
      tecnicoId: (json['tecnicoId'] ?? '').toString(),
      fechaInicio: parseDate(json['fechaInicio']),
      fechaFin: parseDate(json['fechaFin']),
      fechaPago: parseDate(json['fechaPago']),
      totalMonto: parseNum(json['totalMonto']),
      estado: (json['estado'] ?? '').toString(),
      tecnico: tecnicoJson == null
          ? null
          : TechUserSummary.fromJson(tecnicoJson),
      payrollEntryId: payrollEntryJson?['id']?.toString(),
      payrollPeriodId: payrollEntryJson?['periodId']?.toString(),
    );
  }
}

class TechnicalDeparture {
  final String id;
  final String estado;
  final DateTime? fecha;
  final DateTime? horaSalida;
  final DateTime? horaLlegada;
  final DateTime? horaFinal;
  final double? kmEstimados;
  final double? litrosEstimados;
  final double montoCombustible;
  final bool esVehiculoPropio;
  final bool generaPagoCombustible;
  final String? observacion;
  final TechVehicle? vehiculo;
  final TechServiceSummary? servicio;
  final TechUserSummary? tecnico;
  final TechFuelPayment? pagoCombustible;

  const TechnicalDeparture({
    required this.id,
    required this.estado,
    this.fecha,
    this.horaSalida,
    this.horaLlegada,
    this.horaFinal,
    this.kmEstimados,
    this.litrosEstimados,
    required this.montoCombustible,
    required this.esVehiculoPropio,
    required this.generaPagoCombustible,
    this.observacion,
    this.vehiculo,
    this.servicio,
    this.tecnico,
    this.pagoCombustible,
  });

  bool get canMarkArrival => estado.toUpperCase() == 'INICIADA';
  bool get canFinish {
    final upper = estado.toUpperCase();
    return upper == 'INICIADA' || upper == 'LLEGADA';
  }

  factory TechnicalDeparture.fromJson(Map<String, dynamic> json) {
    double? parseNum(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString());
    }

    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      return DateTime.tryParse(value.toString());
    }

    final servicioJson = (json['servicio'] as Map?)?.cast<String, dynamic>();
    final tecnicoJson = (json['tecnico'] as Map?)?.cast<String, dynamic>();
    final pagoJson = (json['pagoCombustible'] as Map?)?.cast<String, dynamic>();

    return TechnicalDeparture(
      id: (json['id'] ?? '').toString(),
      estado: (json['estado'] ?? '').toString(),
      fecha: parseDate(json['fecha']),
      horaSalida: parseDate(json['horaSalida']),
      horaLlegada: parseDate(json['horaLlegada']),
      horaFinal: parseDate(json['horaFinal']),
      kmEstimados: parseNum(json['kmEstimados']),
      litrosEstimados: parseNum(json['litrosEstimados']),
      montoCombustible: parseNum(json['montoCombustible']) ?? 0,
      esVehiculoPropio: json['esVehiculoPropio'] == true,
      generaPagoCombustible: json['generaPagoCombustible'] == true,
      observacion: json['observacion']?.toString(),
      vehiculo: json['vehiculo'] is Map<String, dynamic>
          ? TechVehicle.fromJson(json['vehiculo'] as Map<String, dynamic>)
          : json['vehiculo'] is Map
          ? TechVehicle.fromJson(
              (json['vehiculo'] as Map).cast<String, dynamic>(),
            )
          : null,
      servicio: servicioJson == null
          ? null
          : TechServiceSummary(
              id: (servicioJson['id'] ?? '').toString(),
              title: (servicioJson['title'] ?? 'Servicio').toString(),
              status: (servicioJson['status'] ?? '').toString(),
              orderState: (servicioJson['orderState'] ?? '').toString(),
            ),
      tecnico: tecnicoJson == null
          ? null
          : TechUserSummary.fromJson(tecnicoJson),
      pagoCombustible: pagoJson == null
          ? null
          : TechFuelPayment.fromJson(pagoJson),
    );
  }
}
