enum CloseType { capsulas, pos, tienda }

extension CloseTypeX on CloseType {
  String get label {
    switch (this) {
      case CloseType.capsulas:
        return 'Pastilla';
      case CloseType.pos:
        return 'Software';
      case CloseType.tienda:
        return 'Tienda';
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
    }
  }

  static CloseType fromKey(String value) {
    final normalized = value.trim().toUpperCase();
    switch (normalized) {
      case 'CAPSULAS':
      case 'PASTILLA':
        return CloseType.capsulas;
      case 'POS':
        return CloseType.pos;
      case 'TIENDA':
      case 'TIENDA_SOFTWARE':
      default:
        return CloseType.tienda;
    }
  }
}

class CloseModel {
  final String id;
  final CloseType type;
  final DateTime date;
  final String status; // pending/draft/closed
  final double cash;
  final double transfer;
  final String? transferBank;
  final double card;
  final double expenses;
  final double cashDelivered;
  final String? createdById;
  final String? createdByName;
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
    required this.expenses,
    required this.cashDelivered,
    this.createdById,
    this.createdByName,
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
      expenses: (json['expenses'] as num).toDouble(),
      cashDelivered: (json['cashDelivered'] as num).toDouble(),
      createdById: json['createdById'] as String?,
      createdByName: json['createdByName'] as String?,
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }

  double get incomeTotal => cash + transfer + card;
  double get difference => cashDelivered - (cash - expenses);
}