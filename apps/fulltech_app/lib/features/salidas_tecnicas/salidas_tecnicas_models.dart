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
    );
  }
}
