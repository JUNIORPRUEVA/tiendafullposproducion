import 'dart:convert';

class CotizacionItem {
  final String productId;
  final String nombre;
  final String? imageUrl;
  final double unitPrice;
  final double qty;

  const CotizacionItem({
    required this.productId,
    required this.nombre,
    required this.imageUrl,
    required this.unitPrice,
    required this.qty,
  });

  double get total => unitPrice * qty;

  CotizacionItem copyWith({
    String? productId,
    String? nombre,
    String? imageUrl,
    double? unitPrice,
    double? qty,
  }) {
    return CotizacionItem(
      productId: productId ?? this.productId,
      nombre: nombre ?? this.nombre,
      imageUrl: imageUrl ?? this.imageUrl,
      unitPrice: unitPrice ?? this.unitPrice,
      qty: qty ?? this.qty,
    );
  }

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'nombre': nombre,
    'imageUrl': imageUrl,
    'unitPrice': unitPrice,
    'qty': qty,
  };

  Map<String, dynamic> toCreateDto() => {
    if (_isUuid(productId)) 'productId': productId,
    'productName': nombre,
    if (imageUrl != null && imageUrl!.trim().isNotEmpty)
      'productImageSnapshot': imageUrl,
    'qty': qty,
    'unitPrice': unitPrice,
  };

  static bool _isUuid(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return false;
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(v);
  }

  factory CotizacionItem.fromMap(Map<String, dynamic> map) {
    return CotizacionItem(
      productId: (map['productId'] ?? '').toString(),
      nombre: (map['nombre'] ?? '').toString(),
      imageUrl: map['imageUrl']?.toString(),
      unitPrice: (map['unitPrice'] as num?)?.toDouble() ?? 0,
      qty: (map['qty'] as num?)?.toDouble() ?? 0,
    );
  }

  static double _asDouble(dynamic value, [double fallback = 0]) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    final parsed = double.tryParse(value.toString());
    return parsed ?? fallback;
  }

  factory CotizacionItem.fromApi(Map<String, dynamic> map) {
    return CotizacionItem(
      productId: (map['productId'] ?? '').toString(),
      nombre:
          (map['productNameSnapshot'] ??
                  map['productName'] ??
                  map['nombre'] ??
                  '')
              .toString(),
      imageUrl:
          (map['productImageSnapshot'] ?? map['imageUrl'] ?? map['image_url'])
              ?.toString(),
      unitPrice: _asDouble(map['unitPrice']),
      qty: _asDouble(map['qty']),
    );
  }
}

class CotizacionModel {
  final String id;
  final DateTime createdAt;
  final String? customerId;
  final String customerName;
  final String? customerPhone;
  final String note;
  final bool includeItbis;
  final double itbisRate;
  final List<CotizacionItem> items;

  const CotizacionModel({
    required this.id,
    required this.createdAt,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.note,
    required this.includeItbis,
    required this.itbisRate,
    required this.items,
  });

  double get subtotal => items.fold(0, (sum, item) => sum + item.total);
  double get itbisAmount => includeItbis ? subtotal * itbisRate : 0;
  double get total => subtotal + itbisAmount;

  CotizacionModel copyWith({
    String? id,
    DateTime? createdAt,
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? note,
    bool? includeItbis,
    double? itbisRate,
    List<CotizacionItem>? items,
  }) {
    return CotizacionModel(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      note: note ?? this.note,
      includeItbis: includeItbis ?? this.includeItbis,
      itbisRate: itbisRate ?? this.itbisRate,
      items: items ?? this.items,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'customerId': customerId,
    'customerName': customerName,
    'customerPhone': customerPhone,
    'note': note,
    'includeItbis': includeItbis,
    'itbisRate': itbisRate,
    'items': items.map((item) => item.toMap()).toList(),
  };

  factory CotizacionModel.fromMap(Map<String, dynamic> map) {
    final rawItems = (map['items'] as List?) ?? const [];
    return CotizacionModel(
      id: (map['id'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((map['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      customerId: map['customerId']?.toString(),
      customerName: (map['customerName'] ?? '').toString(),
      customerPhone: map['customerPhone']?.toString(),
      note: (map['note'] ?? '').toString(),
      includeItbis: map['includeItbis'] == true,
      itbisRate: (map['itbisRate'] as num?)?.toDouble() ?? 0.18,
      items: rawItems
          .whereType<Map>()
          .map((row) => CotizacionItem.fromMap(row.cast<String, dynamic>()))
          .toList(),
    );
  }

  static double _asDouble(dynamic value, [double fallback = 0]) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    final parsed = double.tryParse(value.toString());
    return parsed ?? fallback;
  }

  factory CotizacionModel.fromApi(Map<String, dynamic> map) {
    final rawItems = (map['items'] as List?) ?? const [];
    return CotizacionModel(
      id: (map['id'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((map['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      customerId: map['customerId']?.toString(),
      customerName: (map['customerName'] ?? '').toString(),
      customerPhone: map['customerPhone']?.toString(),
      note: (map['note'] ?? '').toString(),
      includeItbis: map['includeItbis'] == true,
      itbisRate: _asDouble(map['itbisRate'], 0.18),
      items: rawItems
          .whereType<Map>()
          .map((row) => CotizacionItem.fromApi(row.cast<String, dynamic>()))
          .toList(),
    );
  }

  Map<String, dynamic> toCreateDto() => {
    if (customerId != null && customerId!.trim().isNotEmpty)
      'customerId': customerId,
    'customerName': customerName,
    'customerPhone': (customerPhone ?? '').trim(),
    if (note.trim().isNotEmpty) 'note': note.trim(),
    'includeItbis': includeItbis,
    'itbisRate': itbisRate,
    'items': items.map((item) => item.toCreateDto()).toList(),
  };

  String toJsonString() => jsonEncode(toMap());

  factory CotizacionModel.fromJsonString(String source) {
    return CotizacionModel.fromMap(
      (jsonDecode(source) as Map).cast<String, dynamic>(),
    );
  }
}

class CotizacionEditorPayload {
  final CotizacionModel source;
  final bool duplicate;

  const CotizacionEditorPayload({
    required this.source,
    required this.duplicate,
  });
}
