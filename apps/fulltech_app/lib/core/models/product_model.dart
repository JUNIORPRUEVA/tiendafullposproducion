import 'package:flutter/foundation.dart';

import '../api/env.dart';
import '../utils/product_image_url.dart';

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

DateTime? _parseDateTimeCandidate(dynamic value) {
  final text = _asNullableString(value);
  if (text == null) return null;
  return DateTime.tryParse(text);
}

DateTime? _firstParsedDate(Iterable<dynamic> values) {
  for (final value in values) {
    final parsed = _parseDateTimeCandidate(value);
    if (parsed != null) return parsed;
  }
  return null;
}

String? _versionFromDate(DateTime? value) {
  if (value == null) return null;
  return value.toUtc().millisecondsSinceEpoch.toString();
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

  if (trimmedBase.isNotEmpty &&
      (url == trimmedBase || url.startsWith('$trimmedBase/'))) {
    return url;
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
  final DateTime? updatedAt;
  final String? categoria;
  final String? imageVersion;

  ProductModel({
    required this.id,
    required this.nombre,
    required this.precio,
    required this.costo,
    this.stock,
    this.categoria,
    this.fotoUrl,
    this.createdAt,
    this.updatedAt,
    this.imageVersion,
  });

  ProductModel copyWith({
    String? id,
    String? nombre,
    double? precio,
    double? costo,
    double? stock,
    String? categoria,
    String? fotoUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? imageVersion,
  }) {
    return ProductModel(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      precio: precio ?? this.precio,
      costo: costo ?? this.costo,
      stock: stock ?? this.stock,
      categoria: categoria ?? this.categoria,
      fotoUrl: fotoUrl ?? this.fotoUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      imageVersion: imageVersion ?? this.imageVersion,
    );
  }

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    final rawStock =
        json['stock'] ?? json['cantidadDisponible'] ?? json['cantidad'];
    final categoria = _asNullableString(
      json['categoria'] ?? json['categoriaNombre'],
    );
    final foto = _asNullableString(json['fotoUrl'] ?? json['imagen']);
    final createdAt = _firstParsedDate([
      json['createdAt'],
      json['created_at'],
    ]);
    final updatedAt = _firstParsedDate([
      json['updatedAt'],
      json['updated_at'],
      json['modifiedAt'],
      json['modified_at'],
      json['fechaActualizacion'],
      json['lastUpdate'],
    ]);
    final imageUpdatedAt = _firstParsedDate([
      json['imageUpdatedAt'],
      json['image_updated_at'],
    ]);
    final explicitImageVersion = _asNullableString(
      json['imageVersion'] ??
          json['catalogSyncVersion'] ??
          json['catalogRefreshVersion'] ??
          json['_catalogSyncVersion'],
    );

    return ProductModel(
      id: _asNullableString(json['id']) ?? '',
      nombre: _asNullableString(json['nombre']) ?? '',
      precio: _asDouble(json['precio']),
      costo: _asDouble(json['costo']),
      stock: _asNullableDouble(rawStock),
      categoria: categoria,
      fotoUrl: _resolveFotoUrl(foto),
      createdAt: createdAt,
      updatedAt: updatedAt,
      imageVersion:
          _versionFromDate(imageUpdatedAt ?? updatedAt) ?? explicitImageVersion,
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
      'updatedAt': updatedAt?.toIso8601String(),
      'imageVersion': imageVersion,
    };
  }

  String? get displayFotoUrl {
    final url = fotoUrl?.trim();
    if (url == null || url.isEmpty) return null;
    return buildProductImageUrl(imageUrl: url, version: imageVersion);
  }

  String get categoriaLabel =>
      (categoria == null || categoria!.isEmpty) ? 'Sin categoría' : categoria!;
}

String buildCatalogSyncVersion(List<ProductModel> items) {
  DateTime? latest;
  for (final item in items) {
    final candidate = item.updatedAt;
    if (candidate == null) continue;
    if (latest == null || candidate.isAfter(latest)) {
      latest = candidate;
    }
  }
  return _versionFromDate(latest) ??
      DateTime.now().toUtc().millisecondsSinceEpoch.toString();
}

List<ProductModel> applyCatalogSyncVersion(
  List<ProductModel> items,
  String syncVersion,
) {
  return items
      .map(
        (item) =>
            (item.imageVersion?.trim().isNotEmpty ?? false)
                ? item
                : item.copyWith(imageVersion: syncVersion),
      )
      .toList(growable: false);
}
