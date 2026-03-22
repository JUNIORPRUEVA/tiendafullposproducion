class ClienteProfileClient {
  final String id;
  final String nombre;
  final String telefono;
  final String phoneNormalized;
  final String? email;
  final String? direccion;
  final String? locationUrl;
  final double? latitude;
  final double? longitude;
  final String? notas;
  final String? ownerId;
  final DateTime? lastActivityAt;
  final bool isDeleted;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ClienteProfileClient({
    required this.id,
    required this.nombre,
    required this.telefono,
    required this.phoneNormalized,
    this.email,
    this.direccion,
    this.locationUrl,
    this.latitude,
    this.longitude,
    this.notas,
    this.ownerId,
    this.lastActivityAt,
    this.isDeleted = false,
    this.createdAt,
    this.updatedAt,
  });

  factory ClienteProfileClient.fromJson(Map<String, dynamic> json) {
    double? parseDouble(dynamic v) {
      if (v == null) return null;
      final n = double.tryParse(v.toString());
      return (n != null && n.isFinite) ? n : null;
    }

    return ClienteProfileClient(
      id: (json['id'] ?? '').toString(),
      nombre: (json['nombre'] ?? '').toString(),
      telefono: (json['telefono'] ?? '').toString(),
      phoneNormalized: (json['phoneNormalized'] ?? '').toString(),
      email: (json['email'] as String?)?.trim().isEmpty == true
          ? null
          : json['email'] as String?,
      direccion: (json['direccion'] as String?)?.trim().isEmpty == true
          ? null
          : json['direccion'] as String?,
      locationUrl:
          ((json['locationUrl'] ?? json['location_url']) as String?)
                  ?.trim()
                  .isEmpty ==
              true
          ? null
          : (json['locationUrl'] ?? json['location_url']) as String?,
      latitude: parseDouble(json['latitude']),
      longitude: parseDouble(json['longitude']),
      notas: (json['notas'] as String?)?.trim().isEmpty == true
          ? null
          : json['notas'] as String?,
      ownerId: (json['ownerId'] as String?)?.trim().isEmpty == true
          ? null
          : json['ownerId'] as String?,
      lastActivityAt: json['lastActivityAt'] != null
          ? DateTime.tryParse(json['lastActivityAt'].toString())
          : null,
      isDeleted: json['isDeleted'] == true,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString())
          : null,
    );
  }
}

class ClienteProfileCreatedBy {
  final String id;
  final String? nombreCompleto;
  final String? email;
  final String? role;

  const ClienteProfileCreatedBy({
    required this.id,
    this.nombreCompleto,
    this.email,
    this.role,
  });

  String get displayName {
    final name = (nombreCompleto ?? '').trim();
    if (name.isNotEmpty) return name;
    final mail = (email ?? '').trim();
    if (mail.isNotEmpty) return mail;
    return id;
  }

  String get label {
    final r = (role ?? '').trim();
    return r.isEmpty ? displayName : '$displayName ($r)';
  }

  factory ClienteProfileCreatedBy.fromJson(Map<String, dynamic> json) {
    return ClienteProfileCreatedBy(
      id: (json['id'] ?? '').toString(),
      nombreCompleto:
          (json['nombreCompleto'] as String?)?.trim().isEmpty == true
          ? null
          : json['nombreCompleto'] as String?,
      email: (json['email'] as String?)?.trim().isEmpty == true
          ? null
          : json['email'] as String?,
      role: (json['role'] as String?)?.trim().isEmpty == true
          ? null
          : json['role'] as String?,
    );
  }
}

class ClienteProfileMetrics {
  final int salesCount;
  final num? salesTotal;
  final DateTime? lastSaleAt;
  final int servicesCount;
  final DateTime? lastServiceAt;
  final int cotizacionesCount;
  final num? cotizacionesTotal;
  final DateTime? lastCotizacionAt;
  final DateTime? lastActivityAt;

  const ClienteProfileMetrics({
    required this.salesCount,
    required this.salesTotal,
    required this.lastSaleAt,
    required this.servicesCount,
    required this.lastServiceAt,
    required this.cotizacionesCount,
    required this.cotizacionesTotal,
    required this.lastCotizacionAt,
    required this.lastActivityAt,
  });

  factory ClienteProfileMetrics.fromJson(Map<String, dynamic> json) {
    return ClienteProfileMetrics(
      salesCount: (json['salesCount'] as num?)?.toInt() ?? 0,
      salesTotal: json['salesTotal'] as num?,
      lastSaleAt: json['lastSaleAt'] != null
          ? DateTime.tryParse(json['lastSaleAt'].toString())
          : null,
      servicesCount: (json['servicesCount'] as num?)?.toInt() ?? 0,
      lastServiceAt: json['lastServiceAt'] != null
          ? DateTime.tryParse(json['lastServiceAt'].toString())
          : null,
      cotizacionesCount: (json['cotizacionesCount'] as num?)?.toInt() ?? 0,
      cotizacionesTotal: json['cotizacionesTotal'] as num?,
      lastCotizacionAt: json['lastCotizacionAt'] != null
          ? DateTime.tryParse(json['lastCotizacionAt'].toString())
          : null,
      lastActivityAt: json['lastActivityAt'] != null
          ? DateTime.tryParse(json['lastActivityAt'].toString())
          : null,
    );
  }
}

class ClienteProfileResponse {
  final ClienteProfileClient client;
  final ClienteProfileMetrics metrics;
  final ClienteProfileCreatedBy? createdBy;

  const ClienteProfileResponse({
    required this.client,
    required this.metrics,
    required this.createdBy,
  });

  factory ClienteProfileResponse.fromJson(Map<String, dynamic> json) {
    final clientRaw =
        (json['client'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final metricsRaw =
        (json['metrics'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final createdByRaw = (json['createdBy'] as Map?)?.cast<String, dynamic>();

    return ClienteProfileResponse(
      client: ClienteProfileClient.fromJson(clientRaw),
      metrics: ClienteProfileMetrics.fromJson(metricsRaw),
      createdBy: createdByRaw == null
          ? null
          : ClienteProfileCreatedBy.fromJson(createdByRaw),
    );
  }
}
