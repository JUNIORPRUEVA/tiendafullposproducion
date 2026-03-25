import '../../core/models/product_model.dart';

class ServiceSalesCommissionItemModel {
  final String orderId;
  final String quotationId;
  final String customerId;
  final String customerName;
  final String category;
  final String serviceType;
  final String status;
  final DateTime? finalizedAt;
  final String createdById;
  final String? technicianId;
  final String? technicianName;
  final String? technicianEmail;
  final int itemsCount;
  final double totalQuoted;
  final double totalCost;
  final double totalProfit;
  final double operationalExpenseRate;
  final double operationalExpenseAmount;
  final double profitAfterExpense;
  final double sellerCommissionRate;
  final double sellerCommissionAmount;
  final double technicianCommissionRate;
  final double technicianCommissionAmount;

  const ServiceSalesCommissionItemModel({
    required this.orderId,
    required this.quotationId,
    required this.customerId,
    required this.customerName,
    required this.category,
    required this.serviceType,
    required this.status,
    required this.finalizedAt,
    required this.createdById,
    required this.technicianId,
    required this.technicianName,
    required this.technicianEmail,
    required this.itemsCount,
    required this.totalQuoted,
    required this.totalCost,
    required this.totalProfit,
    required this.operationalExpenseRate,
    required this.operationalExpenseAmount,
    required this.profitAfterExpense,
    required this.sellerCommissionRate,
    required this.sellerCommissionAmount,
    required this.technicianCommissionRate,
    required this.technicianCommissionAmount,
  });

  factory ServiceSalesCommissionItemModel.fromJson(Map<String, dynamic> json) {
    return ServiceSalesCommissionItemModel(
      orderId: (json['orderId'] ?? '').toString(),
      quotationId: (json['quotationId'] ?? '').toString(),
      customerId: (json['customerId'] ?? '').toString(),
      customerName: (json['customerName'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      serviceType: (json['serviceType'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      finalizedAt: json['finalizedAt'] != null
          ? DateTime.tryParse(json['finalizedAt'].toString())
          : null,
      createdById: (json['createdById'] ?? '').toString(),
      technicianId: json['technicianId']?.toString(),
      technicianName: json['technicianName']?.toString(),
      technicianEmail: json['technicianEmail']?.toString(),
      itemsCount: (json['itemsCount'] as num?)?.toInt() ?? 0,
      totalQuoted: _toDouble(json['totalQuoted']),
      totalCost: _toDouble(json['totalCost']),
      totalProfit: _toDouble(json['totalProfit']),
      operationalExpenseRate: _toDouble(json['operationalExpenseRate']),
      operationalExpenseAmount: _toDouble(json['operationalExpenseAmount']),
      profitAfterExpense: _toDouble(json['profitAfterExpense']),
      sellerCommissionRate: _toDouble(json['sellerCommissionRate']),
      sellerCommissionAmount: _toDouble(json['sellerCommissionAmount']),
      technicianCommissionRate: _toDouble(json['technicianCommissionRate']),
      technicianCommissionAmount: _toDouble(json['technicianCommissionAmount']),
    );
  }
}

class SkippedServiceSalesOrderModel {
  final String orderId;
  final String quotationId;
  final String customerId;
  final String customerName;
  final String category;
  final String serviceType;
  final String status;
  final DateTime? finalizedAt;
  final String createdById;
  final String? technicianId;
  final String? technicianName;
  final String reason;
  final int itemsCount;
  final int missingCostItemsCount;
  final double totalQuoted;

  const SkippedServiceSalesOrderModel({
    required this.orderId,
    required this.quotationId,
    required this.customerId,
    required this.customerName,
    required this.category,
    required this.serviceType,
    required this.status,
    required this.finalizedAt,
    required this.createdById,
    required this.technicianId,
    required this.technicianName,
    required this.reason,
    required this.itemsCount,
    required this.missingCostItemsCount,
    required this.totalQuoted,
  });

  factory SkippedServiceSalesOrderModel.fromJson(Map<String, dynamic> json) {
    return SkippedServiceSalesOrderModel(
      orderId: (json['orderId'] ?? '').toString(),
      quotationId: (json['quotationId'] ?? '').toString(),
      customerId: (json['customerId'] ?? '').toString(),
      customerName: (json['customerName'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      serviceType: (json['serviceType'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      finalizedAt: json['finalizedAt'] != null
          ? DateTime.tryParse(json['finalizedAt'].toString())
          : null,
      createdById: (json['createdById'] ?? '').toString(),
      technicianId: json['technicianId']?.toString(),
      technicianName: json['technicianName']?.toString(),
      reason: (json['reason'] ?? '').toString(),
      itemsCount: (json['itemsCount'] as num?)?.toInt() ?? 0,
      missingCostItemsCount: (json['missingCostItemsCount'] as num?)?.toInt() ?? 0,
      totalQuoted: _toDouble(json['totalQuoted']),
    );
  }
}

class ServiceSalesSummaryModel {
  final DateTime? from;
  final DateTime? to;
  final int totalOrders;
  final int eligibleOrders;
  final int skippedOrders;
  final double totalQuoted;
  final double totalCost;
  final double totalProfit;
  final double totalOperationalExpense;
  final double totalProfitAfterExpense;
  final double totalSellerCommission;
  final double totalTechnicianCommission;
  final List<ServiceSalesCommissionItemModel> items;
  final List<SkippedServiceSalesOrderModel> skipped;

  const ServiceSalesSummaryModel({
    required this.from,
    required this.to,
    required this.totalOrders,
    required this.eligibleOrders,
    required this.skippedOrders,
    required this.totalQuoted,
    required this.totalCost,
    required this.totalProfit,
    required this.totalOperationalExpense,
    required this.totalProfitAfterExpense,
    required this.totalSellerCommission,
    required this.totalTechnicianCommission,
    required this.items,
    required this.skipped,
  });

  factory ServiceSalesSummaryModel.empty() => const ServiceSalesSummaryModel(
    from: null,
    to: null,
    totalOrders: 0,
    eligibleOrders: 0,
    skippedOrders: 0,
    totalQuoted: 0,
    totalCost: 0,
    totalProfit: 0,
    totalOperationalExpense: 0,
    totalProfitAfterExpense: 0,
    totalSellerCommission: 0,
    totalTechnicianCommission: 0,
    items: [],
    skipped: [],
  );

  bool get hasActivity => totalOrders > 0 || items.isNotEmpty || skipped.isNotEmpty;

  factory ServiceSalesSummaryModel.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List?) ?? const [];
    final rawSkipped = (json['skipped'] as List?) ?? const [];
    return ServiceSalesSummaryModel(
      from: json['from'] != null ? DateTime.tryParse(json['from'].toString()) : null,
      to: json['to'] != null ? DateTime.tryParse(json['to'].toString()) : null,
      totalOrders: (json['totalOrders'] as num?)?.toInt() ?? 0,
      eligibleOrders: (json['eligibleOrders'] as num?)?.toInt() ?? 0,
      skippedOrders: (json['skippedOrders'] as num?)?.toInt() ?? 0,
      totalQuoted: _toDouble(json['totalQuoted']),
      totalCost: _toDouble(json['totalCost']),
      totalProfit: _toDouble(json['totalProfit']),
      totalOperationalExpense: _toDouble(json['totalOperationalExpense']),
      totalProfitAfterExpense: _toDouble(json['totalProfitAfterExpense']),
      totalSellerCommission: _toDouble(json['totalSellerCommission']),
      totalTechnicianCommission: _toDouble(json['totalTechnicianCommission']),
      items: rawItems
          .whereType<Map>()
          .map((item) => ServiceSalesCommissionItemModel.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false),
      skipped: rawSkipped
          .whereType<Map>()
          .map((item) => SkippedServiceSalesOrderModel.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }
}

class SalesSummaryModel {
  final int totalSales;
  final double totalSold;
  final double totalCost;
  final double totalProfit;
  final double totalCommission;

  const SalesSummaryModel({
    required this.totalSales,
    required this.totalSold,
    required this.totalCost,
    required this.totalProfit,
    required this.totalCommission,
  });

  factory SalesSummaryModel.empty() => const SalesSummaryModel(
    totalSales: 0,
    totalSold: 0,
    totalCost: 0,
    totalProfit: 0,
    totalCommission: 0,
  );

  factory SalesSummaryModel.fromJson(Map<String, dynamic> json) {
    return SalesSummaryModel(
      totalSales: (json['totalSales'] as num?)?.toInt() ?? 0,
      totalSold: _toDouble(json['totalSold']),
      totalCost: _toDouble(json['totalCost']),
      totalProfit: _toDouble(json['totalProfit']),
      totalCommission: _toDouble(json['totalCommission']),
    );
  }
}

class SaleItemModel {
  final String id;
  final String? productId;
  final String productNameSnapshot;
  final String? productImageSnapshot;
  final double qty;
  final double priceSoldUnit;
  final double costUnitSnapshot;
  final double subtotalSold;
  final double subtotalCost;
  final double profit;

  const SaleItemModel({
    required this.id,
    required this.productId,
    required this.productNameSnapshot,
    required this.productImageSnapshot,
    required this.qty,
    required this.priceSoldUnit,
    required this.costUnitSnapshot,
    required this.subtotalSold,
    required this.subtotalCost,
    required this.profit,
  });

  factory SaleItemModel.fromJson(Map<String, dynamic> json) {
    return SaleItemModel(
      id: (json['id'] ?? '').toString(),
      productId: json['productId']?.toString(),
      productNameSnapshot: (json['productNameSnapshot'] ?? '').toString(),
      productImageSnapshot: json['productImageSnapshot']?.toString(),
      qty: _toDouble(json['qty']),
      priceSoldUnit: _toDouble(json['priceSoldUnit']),
      costUnitSnapshot: _toDouble(json['costUnitSnapshot']),
      subtotalSold: _toDouble(json['subtotalSold']),
      subtotalCost: _toDouble(json['subtotalCost']),
      profit: _toDouble(json['profit']),
    );
  }
}

class SaleModel {
  final String id;
  final String userId;
  final String? customerId;
  final String? customerName;
  final DateTime? saleDate;
  final String? note;
  final double totalSold;
  final double totalCost;
  final double totalProfit;
  final double commissionAmount;
  final List<SaleItemModel> items;

  const SaleModel({
    required this.id,
    required this.userId,
    required this.customerId,
    required this.customerName,
    required this.saleDate,
    required this.note,
    required this.totalSold,
    required this.totalCost,
    required this.totalProfit,
    required this.commissionAmount,
    required this.items,
  });

  factory SaleModel.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List?) ?? const [];
    final customer = json['customer'];
    String? customerName;
    String? customerId;
    if (customer is Map) {
      customerName = customer['nombre']?.toString();
      customerId = customer['id']?.toString();
    }

    return SaleModel(
      id: (json['id'] ?? '').toString(),
      userId: (json['userId'] ?? '').toString(),
      customerId: json['customerId']?.toString() ?? customerId,
      customerName: customerName,
      saleDate: json['saleDate'] != null
          ? DateTime.tryParse(json['saleDate'].toString())
          : null,
      note: json['note']?.toString(),
      totalSold: _toDouble(json['totalSold']),
      totalCost: _toDouble(json['totalCost']),
      totalProfit: _toDouble(json['totalProfit']),
      commissionAmount: _toDouble(json['commissionAmount']),
      items: rawItems
          .whereType<Map>()
          .map((item) => SaleItemModel.fromJson(item.cast<String, dynamic>()))
          .toList(),
    );
  }
}

class SaleDraftItem {
  final ProductModel? product;
  final String? productId;
  final String name;
  final String? imageUrl;
  final bool isExternal;
  final double qty;
  final double priceSoldUnit;
  final double costUnitSnapshot;

  const SaleDraftItem({
    this.product,
    this.productId,
    required this.name,
    required this.imageUrl,
    required this.isExternal,
    required this.qty,
    required this.priceSoldUnit,
    required this.costUnitSnapshot,
  });

  double get subtotalSold => qty * priceSoldUnit;
  double get subtotalCost => qty * costUnitSnapshot;
  double get profit => subtotalSold - subtotalCost;

  SaleDraftItem copyWith({
    ProductModel? product,
    String? productId,
    String? name,
    String? imageUrl,
    bool? isExternal,
    double? qty,
    double? priceSoldUnit,
    double? costUnitSnapshot,
  }) {
    return SaleDraftItem(
      product: product ?? this.product,
      productId: productId ?? this.productId,
      name: name ?? this.name,
      imageUrl: imageUrl ?? this.imageUrl,
      isExternal: isExternal ?? this.isExternal,
      qty: qty ?? this.qty,
      priceSoldUnit: priceSoldUnit ?? this.priceSoldUnit,
      costUnitSnapshot: costUnitSnapshot ?? this.costUnitSnapshot,
    );
  }

  Map<String, dynamic> toPayload() {
    return {
      if (productId != null) 'productId': productId,
      if (productId == null) 'productName': name,
      'qty': qty,
      'priceSoldUnit': priceSoldUnit,
      if (productId == null) 'costUnitSnapshot': costUnitSnapshot,
    };
  }
}

class SalesDateRange {
  final DateTime from;
  final DateTime to;

  const SalesDateRange({required this.from, required this.to});
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value == null) return 0;
  return double.tryParse(value.toString()) ?? 0;
}
