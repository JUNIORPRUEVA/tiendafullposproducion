double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  final s = value.toString().trim();
  if (s.isEmpty) return 0;
  return double.tryParse(s) ?? 0;
}

DateTime? _toDateTime(dynamic value) {
  if (value == null) return null;
  final s = value.toString().trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

class ServiceMiniModel {
  final String id;
  final String title;
  final String status;
  final String? orderState;
  final DateTime? scheduledStart;

  const ServiceMiniModel({
    required this.id,
    required this.title,
    required this.status,
    required this.orderState,
    required this.scheduledStart,
  });

  factory ServiceMiniModel.fromJson(Map<String, dynamic> json) {
    return ServiceMiniModel(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      orderState: json['orderState']?.toString(),
      scheduledStart: _toDateTime(json['scheduledStart']),
    );
  }
}

class VehiculoModel {
  final String id;
  final String nombre;
  final String tipo;
  final String? placa;
  final String combustibleTipo;
  final double rendimientoKmLitro;
  final bool esEmpresa;
  final bool activo;

  const VehiculoModel({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.placa,
    required this.combustibleTipo,
    required this.rendimientoKmLitro,
    required this.esEmpresa,
    required this.activo,
  });

  factory VehiculoModel.fromJson(Map<String, dynamic> json) {
    return VehiculoModel(
      id: (json['id'] ?? '').toString(),
      nombre: (json['nombre'] ?? '').toString(),
      tipo: (json['tipo'] ?? '').toString(),
      placa: json['placa']?.toString(),
      combustibleTipo: (json['combustibleTipo'] ?? '').toString(),
      rendimientoKmLitro: _toDouble(json['rendimientoKmLitro']),
      esEmpresa: (json['esEmpresa'] as bool?) ?? false,
      activo: (json['activo'] as bool?) ?? true,
    );
  }

  String get label {
    final placaShort = (placa ?? '').trim();
    final base = nombre.trim().isEmpty ? 'Vehículo' : nombre.trim();
    if (placaShort.isEmpty) return base;
    return '$base ($placaShort)';
  }
}

class SalidaTecnicaModel {
  final String id;
  final String estado;
  final bool esVehiculoPropio;
  final bool generaPagoCombustible;
  final DateTime? fecha;
  final DateTime? horaSalida;
  final DateTime? horaLlegada;
  final DateTime? horaFinal;
  final double kmEstimados;
  final double litrosEstimados;
  final double montoCombustible;
  final String? observacion;
  final VehiculoModel? vehiculo;
  final ServiceMiniModel? servicio;

  const SalidaTecnicaModel({
    required this.id,
    required this.estado,
    required this.esVehiculoPropio,
    required this.generaPagoCombustible,
    required this.fecha,
    required this.horaSalida,
    required this.horaLlegada,
    required this.horaFinal,
    required this.kmEstimados,
    required this.litrosEstimados,
    required this.montoCombustible,
    required this.observacion,
    required this.vehiculo,
    required this.servicio,
  });

  factory SalidaTecnicaModel.fromJson(Map<String, dynamic> json) {
    final vehiculo = json['vehiculo'];
    final servicio = json['servicio'];

    return SalidaTecnicaModel(
      id: (json['id'] ?? '').toString(),
      estado: (json['estado'] ?? '').toString(),
      esVehiculoPropio: (json['esVehiculoPropio'] as bool?) ?? false,
      generaPagoCombustible: (json['generaPagoCombustible'] as bool?) ?? false,
      fecha: _toDateTime(json['fecha']),
      horaSalida: _toDateTime(json['horaSalida']),
      horaLlegada: _toDateTime(json['horaLlegada']),
      horaFinal: _toDateTime(json['horaFinal']),
      kmEstimados: _toDouble(json['kmEstimados']),
      litrosEstimados: _toDouble(json['litrosEstimados']),
      montoCombustible: _toDouble(json['montoCombustible']),
      observacion: json['observacion']?.toString(),
      vehiculo: vehiculo is Map ? VehiculoModel.fromJson(vehiculo.cast<String, dynamic>()) : null,
      servicio: servicio is Map ? ServiceMiniModel.fromJson(servicio.cast<String, dynamic>()) : null,
    );
  }
}
