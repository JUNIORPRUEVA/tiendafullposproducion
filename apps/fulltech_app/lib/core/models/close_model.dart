enum CloseType { capsulas, pos, tienda, phytoemagry }

extension CloseTypeX on CloseType {
  String get label {
    switch (this) {
      case CloseType.capsulas:
        return 'Pastilla';
      case CloseType.pos:
        return 'Software';
      case CloseType.tienda:
        return 'Tienda';
      case CloseType.phytoemagry:
        return 'PhytoEmagry';
    }
  }

  String get apiValue {
    switch (this) {
      case CloseType.capsulas:
        return 'CAPSULAS';
      case CloseType.pos:
        return 'POS';
      case CloseType.tienda:
        return 'TIENDA';
      case CloseType.phytoemagry:
        return 'PHYTOEMAGRY';
    }
  }

  static CloseType fromKey(String value) {
    final normalized = value.trim().toUpperCase();
    switch (normalized) {
      case 'POS':
        return CloseType.pos;
      case 'TIENDA':
      case 'TIENDA_SOFTWARE':
        return CloseType.tienda;
      case 'PHYTOEMAGRY':
      case 'PHYTO':
      case 'CAPSULAS':
      case 'PASTILLA':
        return CloseType.phytoemagry;
      default:
        return CloseType.tienda;
    }
  }
}

class CloseModel {
  final String id;
  final CloseType type;
  final DateTime date;
  final String status; // pending/approved/rejected
  final double cash;
  final double transfer;
  final String? transferBank;
  final double card;
  final double otherIncome;
  final double expenses;
  final double cashDelivered;
  final String? notes;
  final String? evidenceUrl;
  final String? evidenceFileName;
  final String? createdById;
  final String? createdByName;
  final String? reviewedById;
  final String? reviewedByName;
  final DateTime? reviewedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CloseModel({
    required this.id,
    required this.type,
    required this.date,
    required this.status,
    required this.cash,
    required this.transfer,
    this.transferBank,
    required this.card,
    this.otherIncome = 0,
    required this.expenses,
    required this.cashDelivered,
    this.notes,
    this.evidenceUrl,
    this.evidenceFileName,
    this.createdById,
    this.createdByName,
    this.reviewedById,
    this.reviewedByName,
    this.reviewedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CloseModel.fromJson(Map<String, dynamic> json) {
    return CloseModel(
      id: json['id'],
      type: CloseTypeX.fromKey(json['type']),
      date: DateTime.parse(json['date']),
      status: json['status'],
      cash: (json['cash'] as num).toDouble(),
      transfer: (json['transfer'] as num).toDouble(),
      transferBank: (json['transferBank'] as String?)?.trim().isEmpty == true
          ? null
          : json['transferBank'] as String?,
      card: (json['card'] as num).toDouble(),
      otherIncome: (json['otherIncome'] as num?)?.toDouble() ?? 0,
      expenses: (json['expenses'] as num).toDouble(),
      cashDelivered: (json['cashDelivered'] as num).toDouble(),
      notes: json['notes'] as String?,
      evidenceUrl: json['evidenceUrl'] as String?,
      evidenceFileName: json['evidenceFileName'] as String?,
      createdById: json['createdById'] as String?,
      createdByName: json['createdByName'] as String?,
      reviewedById: json['reviewedById'] as String?,
      reviewedByName: json['reviewedByName'] as String?,
      reviewedAt: json['reviewedAt'] == null
          ? null
          : DateTime.parse(json['reviewedAt']),
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }

  double get incomeTotal => cash + transfer + card + otherIncome;
  double get netTotal => incomeTotal - expenses;
  double get difference => cash - cashDelivered;
  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
}
