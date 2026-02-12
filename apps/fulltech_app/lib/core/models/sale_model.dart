double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

int _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

class SaleItemModel {
  final String id;
  final String productId;
  final String productName;
  final int qty;
  final double unitPrice;
  final double unitCost;
  final double lineTotal;
  final double lineCost;
  final double lineProfit;

  const SaleItemModel({
    required this.id,
    required this.productId,
    required this.productName,
    required this.qty,
    required this.unitPrice,
    required this.unitCost,
    required this.lineTotal,
    required this.lineCost,
    required this.lineProfit,
  });

  factory SaleItemModel.fromJson(Map<String, dynamic> json) {
    final product = (json['product'] as Map?)?.cast<String, dynamic>();
    return SaleItemModel(
      id: json['id'] ?? '',
      productId: json['productId'] ?? product?['id'] ?? '',
      productName: json['productName'] ?? product?['nombre'] ?? product?['name'] ?? '',
      qty: _toInt(json['qty'] ?? json['cantidad'] ?? 0),
      unitPrice: _toDouble(json['unitPriceSold'] ?? json['price'] ?? json['precio'] ?? 0),
      unitCost: _toDouble(json['unitCostSnapshot'] ?? json['costo'] ?? 0),
      lineTotal: _toDouble(json['lineTotal'] ?? json['total'] ?? 0),
      lineCost: _toDouble(json['lineCost'] ?? 0),
      lineProfit: _toDouble(json['lineProfit'] ?? json['puntosUtilidad'] ?? 0),
    );
  }
}

class SaleModel {
  final String id;
  final String status;
  final double subtotal;
  final double totalCost;
  final double profit;
  final double commission;
  final String? note;
  final DateTime soldAt;
  final String? clientName;
  final String? sellerName;
  final List<SaleItemModel> items;

  const SaleModel({
    required this.id,
    required this.status,
    required this.subtotal,
    required this.totalCost,
    required this.profit,
    required this.commission,
    required this.note,
    required this.soldAt,
    required this.clientName,
    required this.sellerName,
    required this.items,
  });

  factory SaleModel.fromJson(Map<String, dynamic> json) {
    final client = (json['client'] as Map?)?.cast<String, dynamic>();
    final seller = (json['seller'] as Map?)?.cast<String, dynamic>();
    return SaleModel(
      id: json['id'] ?? '',
      status: json['status'] ?? 'DRAFT',
      subtotal: _toDouble(json['subtotal'] ?? json['total'] ?? json['totalVenta'] ?? 0),
      totalCost: _toDouble(json['totalCost'] ?? json['costo'] ?? 0),
      profit: _toDouble(json['profit'] ?? json['puntosUtilidad'] ?? 0),
      commission: _toDouble(json['commission'] ?? json['comision'] ?? 0),
      note: json['note'] ?? json['nota'],
      soldAt: DateTime.tryParse(json['soldAt'] ?? json['createdAt'] ?? '') ?? DateTime.now(),
      clientName: client?['nombre'] ?? client?['name'] ?? json['clientName'],
      sellerName: seller?['nombreCompleto'] ?? seller?['name'],
      items: ((json['items'] ?? json['saleItems']) as List<dynamic>? ?? [])
          .map((e) => SaleItemModel.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}
