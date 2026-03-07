import 'package:flutter/foundation.dart';

import '../api/env.dart';

String? _asNullableString(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return null;
  return text;
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value == null) return 0;
  final normalized = value.toString().trim().replaceAll(',', '.');
  return double.tryParse(normalized) ?? 0;
}

double? _asNullableDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final normalized = value.toString().trim().replaceAll(',', '.');
  return double.tryParse(normalized);
}

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
    final uploadsPath = extractUploadsPath(url);
    if (kIsWeb && uploadsPath != null && trimmedBase.isNotEmpty) {
      final encodedUrl = Uri.encodeQueryComponent(url);
      return '$trimmedBase/products/image-proxy?url=$encodedUrl';
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
  final double? stock;
  final String? fotoUrl;
  final DateTime? createdAt;
  final String? categoria;

  ProductModel({
    required this.id,
    required this.nombre,
    required this.precio,
    required this.costo,
    this.stock,
    this.categoria,
    this.fotoUrl,
    this.createdAt,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    final rawStock =
        json['stock'] ?? json['cantidadDisponible'] ?? json['cantidad'];
    final categoria = _asNullableString(
      json['categoria'] ?? json['categoriaNombre'],
    );
    final foto = _asNullableString(json['fotoUrl'] ?? json['imagen']);
    final createdAtRaw = _asNullableString(json['createdAt']);

    return ProductModel(
      id: _asNullableString(json['id']) ?? '',
      nombre: _asNullableString(json['nombre']) ?? '',
      precio: _asDouble(json['precio']),
      costo: _asDouble(json['costo']),
      stock: _asNullableDouble(rawStock),
      categoria: categoria,
      fotoUrl: _resolveFotoUrl(foto),
      createdAt: createdAtRaw != null ? DateTime.tryParse(createdAtRaw) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'precio': precio,
      'costo': costo,
      'stock': stock,
      'categoria': categoria,
      'fotoUrl': fotoUrl,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  String get categoriaLabel =>
      (categoria == null || categoria!.isEmpty) ? 'Sin categoría' : categoria!;
}
