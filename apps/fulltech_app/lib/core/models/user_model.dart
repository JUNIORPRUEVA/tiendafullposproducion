class UserModel {
  final String id;
  final String email;
  final String nombreCompleto;
  final String telefono;
  final String? cedula;
  final String? experienciaLaboral;
  final String? role;
  final bool blocked;
  final int? edad;
  final DateTime? createdAt;

  UserModel({
    required this.id,
    required this.email,
    required this.nombreCompleto,
    required this.telefono,
    this.cedula,
    this.experienciaLaboral,
    this.role,
    this.blocked = false,
    this.edad,
    this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      nombreCompleto: json['nombreCompleto'] ?? json['nombre'] ?? '',
      telefono: json['telefono'] ?? '',
      cedula: json['cedula'],
      experienciaLaboral: json['experienciaLaboral'],
      role: json['role'] ?? json['rol'] ?? 'ASISTENTE',
      blocked: json['blocked'] ?? false,
      edad: json['edad'],
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'nombreCompleto': nombreCompleto,
      'telefono': telefono,
      'cedula': cedula,
      'experienciaLaboral': experienciaLaboral,
      'role': role,
      'blocked': blocked,
      'edad': edad,
      'createdAt': createdAt?.toIso8601String(),
    };
  }
}
