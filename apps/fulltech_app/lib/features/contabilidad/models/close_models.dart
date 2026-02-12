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

class CloseSummary {
  final CloseType type;
  final String status; // pending/draft/closed
  final double cash;
  final double transfer;
  final double card;
  final double expenses;
  final double cashDelivered;

  const CloseSummary({
    required this.type,
    required this.status,
    required this.cash,
    required this.transfer,
    required this.card,
    required this.expenses,
    required this.cashDelivered,
  });

  double get incomeTotal => cash + transfer + card;

  double get difference {
    final expectedCash = cash - expenses;
    return cashDelivered - expectedCash;
  }
}
