class SaleItemModel {
  final String id;
  final String productName;
  final double qty;
  final double price;
  final double lineTotal;

  SaleItemModel({required this.id, required this.productName, required this.qty, required this.price, required this.lineTotal});

  factory SaleItemModel.fromJson(Map<String, dynamic> json) {
    return SaleItemModel(
      id: json['id'] ?? '',
      productName: json['productName'] ?? json['product']?['name'] ?? '',
      qty: (json['qty'] ?? json['quantity'] ?? 0).toDouble(),
      price: (json['price'] ?? 0).toDouble(),
      lineTotal: (json['lineTotal'] ?? json['total'] ?? 0).toDouble(),
    );
  }
}

class SaleModel {
  final String id;
  final double total;
  final String? note;
  final DateTime createdAt;
  final List<SaleItemModel> items;

  SaleModel({required this.id, required this.total, required this.note, required this.createdAt, required this.items});

  factory SaleModel.fromJson(Map<String, dynamic> json) {
    return SaleModel(
      id: json['id'] ?? '',
      total: (json['total'] ?? json['totalVenta'] ?? 0).toDouble(),
      note: json['note'] ?? json['nota'],
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      items: ((json['items'] ?? json['saleItems']) as List<dynamic>? ?? [])
          .map((e) => SaleItemModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
