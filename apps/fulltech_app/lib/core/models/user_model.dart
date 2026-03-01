class UserModel {
  final String id;
  final String email;
  final String nombreCompleto;
  final String telefono;
  final String? cedula;
  final String? telefonoFamiliar;
  final String? fotoCedulaUrl;
  final String? fotoLicenciaUrl;
  final String? fotoPersonalUrl;
  final String? experienciaLaboral;
  final DateTime? fechaIngreso;
  final DateTime? fechaNacimiento;
  final String? cuentaNominaPreferencial;
  final List<String> habilidades;
  final String? role;
  final bool blocked;
  final int? edad;
  final bool tieneHijos;
  final bool estaCasado;
  final bool casaPropia;
  final bool vehiculo;
  final bool licenciaConducir;
  final DateTime? createdAt;

  UserModel({
    required this.id,
    required this.email,
    required this.nombreCompleto,
    required this.telefono,
    this.cedula,
    this.telefonoFamiliar,
    this.fotoCedulaUrl,
    this.fotoLicenciaUrl,
    this.fotoPersonalUrl,
    this.experienciaLaboral,
    this.fechaIngreso,
    this.fechaNacimiento,
    this.cuentaNominaPreferencial,
    this.habilidades = const [],
    this.role,
    this.blocked = false,
    this.edad,
    this.tieneHijos = false,
    this.estaCasado = false,
    this.casaPropia = false,
    this.vehiculo = false,
    this.licenciaConducir = false,
    this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final habilidadesRaw = json['habilidades'];
    final habilidades = habilidadesRaw is List
        ? habilidadesRaw
            .whereType<String>()
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: false)
        : const <String>[];

    return UserModel(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      nombreCompleto: json['nombreCompleto'] ?? json['nombre'] ?? '',
      telefono: json['telefono'] ?? '',
      cedula: json['cedula'],
      telefonoFamiliar: json['telefonoFamiliar'],
      fotoCedulaUrl: json['fotoCedulaUrl'],
      fotoLicenciaUrl: json['fotoLicenciaUrl'],
      fotoPersonalUrl: json['fotoPersonalUrl'],
      experienciaLaboral: json['experienciaLaboral'],
      fechaIngreso: json['fechaIngreso'] != null
          ? DateTime.tryParse(json['fechaIngreso'])
          : null,
      fechaNacimiento: json['fechaNacimiento'] != null
          ? DateTime.tryParse(json['fechaNacimiento'])
          : null,
      cuentaNominaPreferencial: json['cuentaNominaPreferencial'],
      habilidades: habilidades,
      role: json['role'] ?? json['rol'] ?? 'ASISTENTE',
      blocked: json['blocked'] ?? false,
      edad: json['edad'],
      tieneHijos: json['tieneHijos'] ?? false,
      estaCasado: json['estaCasado'] ?? false,
      casaPropia: json['casaPropia'] ?? false,
      vehiculo: json['vehiculo'] ?? false,
      licenciaConducir: json['licenciaConducir'] ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'])
          : null,
    );
  }

  int? get diasEnEmpresa {
    if (fechaIngreso == null) return null;
    final start = DateTime(
      fechaIngreso!.year,
      fechaIngreso!.month,
      fechaIngreso!.day,
    );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(start).inDays;
    return diff < 0 ? 0 : diff;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'nombreCompleto': nombreCompleto,
      'telefono': telefono,
      'cedula': cedula,
      'telefonoFamiliar': telefonoFamiliar,
      'fotoCedulaUrl': fotoCedulaUrl,
      'fotoLicenciaUrl': fotoLicenciaUrl,
      'fotoPersonalUrl': fotoPersonalUrl,
      'experienciaLaboral': experienciaLaboral,
      'fechaIngreso': fechaIngreso?.toIso8601String(),
      'fechaNacimiento': fechaNacimiento?.toIso8601String(),
      'cuentaNominaPreferencial': cuentaNominaPreferencial,
      'habilidades': habilidades,
      'role': role,
      'blocked': blocked,
      'edad': edad,
      'tieneHijos': tieneHijos,
      'estaCasado': estaCasado,
      'casaPropia': casaPropia,
      'vehiculo': vehiculo,
      'licenciaConducir': licenciaConducir,
      'createdAt': createdAt?.toIso8601String(),
    };
  }
}
