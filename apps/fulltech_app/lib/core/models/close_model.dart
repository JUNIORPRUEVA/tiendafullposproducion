enum CloseType { capsulas, pos, tienda }

extension CloseTypeX on CloseType {
  String get label {
    switch (this) {
      case CloseType.capsulas:
        return 'Cápsulas';
      case CloseType.pos:
        return 'Punto de Ventas';
      case CloseType.tienda:
        return 'Tienda';
    }
  }

  String get key {
    switch (this) {
      case CloseType.capsulas:
        return 'capsulas';
      case CloseType.pos:
        return 'pos';
      case CloseType.tienda:
        return 'tienda';
    }
  }

  static CloseType fromKey(String value) {
    switch (value) {
      case 'capsulas':
        return CloseType.capsulas;
      case 'pos':
        return CloseType.pos;
      case 'tienda':
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
  final double card;
  final double expenses;
  final double cashDelivered;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CloseModel({
    required this.id,
    required this.type,
    required this.date,
    required this.status,
    required this.cash,
    required this.transfer,
    required this.card,
    required this.expenses,
    required this.cashDelivered,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CloseModel.fromJson(Map<String, dynamic> json) {
    return CloseModel(
      id: json['id'],
      type: CloseType.fromKey(json['type']),
      date: DateTime.parse(json['date']),
      status: json['status'],
      cash: (json['cash'] as num).toDouble(),
      transfer: (json['transfer'] as num).toDouble(),
      card: (json['card'] as num).toDouble(),
      expenses: (json['expenses'] as num).toDouble(),
      cashDelivered: (json['cashDelivered'] as num).toDouble(),
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }

  double get incomeTotal => cash + transfer + card;
  double get difference => cashDelivered - (cash - expenses);
}