class AdminUserLocation {
  final String userId;
  final String nombreCompleto;
  final String email;
  final String role;
  final bool blocked;
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final DateTime updatedAt;

  AdminUserLocation({
    required this.userId,
    required this.nombreCompleto,
    required this.email,
    required this.role,
    required this.blocked,
    required this.latitude,
    required this.longitude,
    required this.updatedAt,
    this.accuracyMeters,
  });

  factory AdminUserLocation.fromJson(Map<String, dynamic> json) {
    final user = (json['user'] as Map? ?? const {}).cast<String, dynamic>();

    final updatedRaw = json['updatedAt'];
    final updatedAt = updatedRaw is String
        ? DateTime.tryParse(updatedRaw) ??
              DateTime.fromMillisecondsSinceEpoch(0)
        : DateTime.fromMillisecondsSinceEpoch(0);

    return AdminUserLocation(
      userId: (json['userId'] ?? '').toString(),
      nombreCompleto: (user['nombreCompleto'] ?? '').toString(),
      email: (user['email'] ?? '').toString(),
      role: (user['role'] ?? '').toString(),
      blocked: user['blocked'] == true,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracyMeters: (json['accuracyMeters'] is num)
          ? (json['accuracyMeters'] as num).toDouble()
          : null,
      updatedAt: updatedAt,
    );
  }
}
