import 'dart:convert';

class QuotationContextItem {
  const QuotationContextItem({
    required this.productId,
    required this.productName,
    required this.category,
    required this.qty,
    required this.unitPrice,
    required this.officialUnitPrice,
    required this.lineTotal,
    this.notes,
  });

  final String productId;
  final String productName;
  final String category;
  final double qty;
  final double unitPrice;
  final double? officialUnitPrice;
  final double lineTotal;
  final String? notes;

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'productName': productName,
    'category': category,
    'qty': qty,
    'unitPrice': unitPrice,
    'officialUnitPrice': officialUnitPrice,
    'lineTotal': lineTotal,
    'notes': notes,
  };
}

class QuotationContext {
  const QuotationContext({
    required this.quotationId,
    required this.module,
    required this.productType,
    required this.productName,
    required this.brand,
    required this.quantity,
    required this.installationType,
    required this.selectedPriceType,
    required this.selectedUnitPrice,
    required this.selectedTotal,
    required this.minimumPrice,
    required this.offerPrice,
    required this.normalPrice,
    required this.components,
    required this.notes,
    required this.extraCharges,
    required this.currentDvrType,
    required this.requiredDvrType,
    required this.screenName,
    required this.items,
    required this.metadata,
  });

  final String? quotationId;
  final String module;
  final String? productType;
  final String? productName;
  final String? brand;
  final double quantity;
  final String? installationType;
  final String? selectedPriceType;
  final double? selectedUnitPrice;
  final double selectedTotal;
  final double? minimumPrice;
  final double? offerPrice;
  final double? normalPrice;
  final List<String> components;
  final String? notes;
  final List<String> extraCharges;
  final String? currentDvrType;
  final String? requiredDvrType;
  final String screenName;
  final List<QuotationContextItem> items;
  final Map<String, dynamic> metadata;

  String get signature => jsonEncode(toMap());

  Map<String, dynamic> toMap() => {
    'quotationId': quotationId,
    'module': module,
    'productType': productType,
    'productName': productName,
    'brand': brand,
    'quantity': quantity,
    'installationType': installationType,
    'selectedPriceType': selectedPriceType,
    'selectedUnitPrice': selectedUnitPrice,
    'selectedTotal': selectedTotal,
    'minimumPrice': minimumPrice,
    'offerPrice': offerPrice,
    'normalPrice': normalPrice,
    'components': components,
    'notes': notes,
    'extraCharges': extraCharges,
    'currentDvrType': currentDvrType,
    'requiredDvrType': requiredDvrType,
    'screenName': screenName,
    'items': items.map((item) => item.toMap()).toList(growable: false),
    'metadata': metadata,
  };
}
