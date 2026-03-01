import '../api/env.dart';

String? _resolveFotoUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  final base = Env.apiBaseUrl;
  final trimmedBase = base.endsWith('/')
      ? base.substring(0, base.length - 1)
      : base;

  String? extractUploadsPath(String value) {
    final normalized = value.replaceAll('\\\\', '/').trim();
    const marker = '/uploads/';
    final markerIndex = normalized.indexOf(marker);
    if (markerIndex >= 0) {
      return normalized.substring(markerIndex);
    }
    if (normalized.startsWith('uploads/')) {
      return '/$normalized';
    }
    if (normalized.startsWith('./uploads/')) {
      return normalized.substring(1);
    }
    return null;
  }

  if (url.startsWith('http://') || url.startsWith('https://')) {
    try {
      final parsed = Uri.parse(url);
      final path = extractUploadsPath(parsed.path);
      final isUploadsPath = path != null;
      if (isUploadsPath && trimmedBase.isNotEmpty) {
        final query = parsed.hasQuery ? '?${parsed.query}' : '';
        return '$trimmedBase$path$query';
      }
    } catch (_) {
      return url;
    }
    return url;
  }

  final uploadsPath = extractUploadsPath(url);
  if (uploadsPath != null) {
    if (trimmedBase.isEmpty) return uploadsPath;
    return '$trimmedBase$uploadsPath';
  }

  if (trimmedBase.isEmpty) return url;
  final normalizedPath = url.startsWith('/') ? url : '/$url';
  return '$trimmedBase$normalizedPath';
}

class ProductModel {
  final String id;
  final String nombre;
  final double precio;
  final double costo;
  final String? fotoUrl;
  final DateTime? createdAt;
  final String? categoria;

  ProductModel({
    required this.id,
    required this.nombre,
    required this.precio,
    required this.costo,
    this.categoria,
    this.fotoUrl,
    this.createdAt,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: json['id'] ?? '',
      nombre: json['nombre'] ?? '',
      precio: (json['precio'] is num)
          ? (json['precio'] as num).toDouble()
          : double.tryParse(json['precio']?.toString() ?? '') ?? 0,
      costo: (json['costo'] is num)
          ? (json['costo'] as num).toDouble()
          : double.tryParse(json['costo']?.toString() ?? '') ?? 0,
      categoria:
          json['categoria'] as String? ?? json['categoriaNombre'] as String?,
      fotoUrl: _resolveFotoUrl((json['fotoUrl'] ?? json['imagen']) as String?),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'precio': precio,
      'costo': costo,
      'categoria': categoria,
      'fotoUrl': fotoUrl,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  String get categoriaLabel =>
      (categoria == null || categoria!.isEmpty) ? 'Sin categoría' : categoria!;
}
