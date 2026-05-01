enum CloseType { capsulas, pos, tienda, phytoemagry }

extension CloseTypeX on CloseType {
  String get label {
    switch (this) {
      case CloseType.capsulas:
        return 'Cápsulas';
      case CloseType.pos:
        return 'POS';
      case CloseType.tienda:
        return 'Tienda';
      case CloseType.phytoemagry:
        return 'PhytoEmagry';
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
      case CloseType.phytoemagry:
        return 'phytoemagry';
    }
  }

  static CloseType fromKey(String value) {
    switch (value.trim().toLowerCase()) {
      case 'pos':
        return CloseType.pos;
      case 'tienda':
        return CloseType.tienda;
      case 'phytoemagry':
      case 'phyto':
      case 'capsulas':
        return CloseType.phytoemagry;
      default:
        return CloseType.tienda;
    }
  }
}

class CloseSummary {
  final CloseType type;
  final String status; // pending/approved/rejected
  final double cash;
  final double transfer;
  final double card;
  final double otherIncome;
  final double expenses;
  final double cashDelivered;

  const CloseSummary({
    required this.type,
    required this.status,
    required this.cash,
    required this.transfer,
    required this.card,
    this.otherIncome = 0,
    required this.expenses,
    required this.cashDelivered,
  });

  double get incomeTotal => cash + transfer + card + otherIncome;
  double get netTotal => incomeTotal - expenses;

  double get difference => cash - cashDelivered;
}
