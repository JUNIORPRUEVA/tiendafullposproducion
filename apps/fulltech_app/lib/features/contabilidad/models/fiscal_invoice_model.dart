enum FiscalInvoiceKind { sale, purchase }

extension FiscalInvoiceKindX on FiscalInvoiceKind {
  String get apiValue {
    switch (this) {
      case FiscalInvoiceKind.sale:
        return 'SALE';
      case FiscalInvoiceKind.purchase:
        return 'PURCHASE';
    }
  }

  String get label {
    switch (this) {
      case FiscalInvoiceKind.sale:
        return 'Ventas';
      case FiscalInvoiceKind.purchase:
        return 'Compras';
    }
  }

  static FiscalInvoiceKind fromApi(String raw) {
    final value = raw.trim().toUpperCase();
    switch (value) {
      case 'PURCHASE':
        return FiscalInvoiceKind.purchase;
      case 'SALE':
      default:
        return FiscalInvoiceKind.sale;
    }
  }
}

class FiscalInvoiceModel {
  final String id;
  final FiscalInvoiceKind kind;
  final DateTime invoiceDate;
  final String imageUrl;
  final String? note;
  final String? createdById;
  final String? createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FiscalInvoiceModel({
    required this.id,
    required this.kind,
    required this.invoiceDate,
    required this.imageUrl,
    this.note,
    this.createdById,
    this.createdByName,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FiscalInvoiceModel.fromJson(Map<String, dynamic> json) {
    return FiscalInvoiceModel(
      id: (json['id'] ?? '').toString(),
      kind: FiscalInvoiceKindX.fromApi((json['kind'] ?? 'SALE').toString()),
      invoiceDate: DateTime.parse(json['invoiceDate'].toString()),
      imageUrl: (json['imageUrl'] ?? '').toString(),
      note: (json['note'] as String?)?.trim().isEmpty == true
          ? null
          : json['note'] as String?,
      createdById: json['createdById'] as String?,
      createdByName: json['createdByName'] as String?,
      createdAt: DateTime.parse(json['createdAt'].toString()),
      updatedAt: DateTime.parse(json['updatedAt'].toString()),
    );
  }
}
