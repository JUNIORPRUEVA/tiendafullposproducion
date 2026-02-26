import '../api/env.dart';

String? _resolveFotoUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('http://') || url.startsWith('https://')) {
    try {
      final parsed = Uri.parse(url);
      final host = parsed.host.toLowerCase();
      if (host == 'localhost' || host == '127.0.0.1' || host == '0.0.0.0') {
        final base = Env.apiBaseUrl;
        if (base.isEmpty) return url;
        final trimmedBase = base.endsWith('/')
            ? base.substring(0, base.length - 1)
            : base;
        final path = parsed.path.startsWith('/') ? parsed.path : '/${parsed.path}';
        final query = parsed.hasQuery ? '?${parsed.query}' : '';
        return '$trimmedBase$path$query';
      }
    } catch (_) {
      return url;
    }
    return url;
  }
  final base = Env.apiBaseUrl;
  if (base.isEmpty) return url;
  final trimmedBase = base.endsWith('/')
      ? base.substring(0, base.length - 1)
      : base;
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

  String get categoriaLabel =>
      (categoria == null || categoria!.isEmpty) ? 'Sin categoría' : categoria!;
}
