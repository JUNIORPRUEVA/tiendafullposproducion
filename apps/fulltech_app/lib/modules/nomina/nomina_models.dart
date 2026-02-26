 enum PayrollPeriodStatus { open, closed }

enum PayrollEntryType {
  faltaDia,
  tarde,
  bono,
  comision,
  adelanto,
  descuento,
  otro,
}

extension PayrollPeriodStatusX on PayrollPeriodStatus {
  String get dbValue => this == PayrollPeriodStatus.open ? 'OPEN' : 'CLOSED';

  String get label => this == PayrollPeriodStatus.open ? 'Abierta' : 'Cerrada';

  static PayrollPeriodStatus fromDb(String value) {
    return value.toUpperCase() == 'CLOSED'
        ? PayrollPeriodStatus.closed
        : PayrollPeriodStatus.open;
  }
}

extension PayrollEntryTypeX on PayrollEntryType {
  String get dbValue {
    switch (this) {
      case PayrollEntryType.faltaDia:
        return 'FALTA_DIA';
      case PayrollEntryType.tarde:
        return 'TARDE';
      case PayrollEntryType.bono:
        return 'BONO';
      case PayrollEntryType.comision:
        return 'COMISION';
      case PayrollEntryType.adelanto:
        return 'ADELANTO';
      case PayrollEntryType.descuento:
        return 'DESCUENTO';
      case PayrollEntryType.otro:
        return 'OTRO';
    }
  }

  String get label {
    switch (this) {
      case PayrollEntryType.faltaDia:
        return 'Falta de día';
      case PayrollEntryType.tarde:
        return 'Llegada tarde';
      case PayrollEntryType.bono:
        return 'Bono';
      case PayrollEntryType.comision:
        return 'Comisión';
      case PayrollEntryType.adelanto:
        return 'Adelanto';
      case PayrollEntryType.descuento:
        return 'Descuento';
      case PayrollEntryType.otro:
        return 'Otro';
    }
  }

  bool get isDeduction {
    return this == PayrollEntryType.faltaDia ||
        this == PayrollEntryType.tarde ||
        this == PayrollEntryType.adelanto ||
        this == PayrollEntryType.descuento;
  }

  static PayrollEntryType fromDb(String value) {
    switch (value.toUpperCase()) {
      case 'FALTA_DIA':
        return PayrollEntryType.faltaDia;
      case 'TARDE':
        return PayrollEntryType.tarde;
      case 'BONO':
        return PayrollEntryType.bono;
      case 'COMISION':
        return PayrollEntryType.comision;
      case 'ADELANTO':
        return PayrollEntryType.adelanto;
      case 'DESCUENTO':
        return PayrollEntryType.descuento;
      case 'OTRO':
      default:
        return PayrollEntryType.otro;
    }
  }
}

class PayrollEmployee {
  final String id;
  final String ownerId;
  final String nombre;
  final String? telefono;
  final String? puesto;
  final double cuotaMinima;
  final double seguroLeyMonto;
  final bool activo;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const PayrollEmployee({
    required this.id,
    required this.ownerId,
    required this.nombre,
    this.telefono,
    this.puesto,
    this.cuotaMinima = 0,
    this.seguroLeyMonto = 0,
    this.activo = true,
    this.createdAt,
    this.updatedAt,
  });

  PayrollEmployee copyWith({
    String? id,
    String? ownerId,
    String? nombre,
    String? telefono,
    String? puesto,
    double? cuotaMinima,
    double? seguroLeyMonto,
    bool? activo,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearTelefono = false,
    bool clearPuesto = false,
  }) {
    return PayrollEmployee(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      nombre: nombre ?? this.nombre,
      telefono: clearTelefono ? null : (telefono ?? this.telefono),
      puesto: clearPuesto ? null : (puesto ?? this.puesto),
      cuotaMinima: cuotaMinima ?? this.cuotaMinima,
      seguroLeyMonto: seguroLeyMonto ?? this.seguroLeyMonto,
      activo: activo ?? this.activo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory PayrollEmployee.fromMap(Map<String, dynamic> map) {
    return PayrollEmployee(
      id: (map['id'] ?? '').toString(),
      ownerId: (map['owner_id'] ?? '').toString(),
      nombre: (map['nombre'] ?? '').toString(),
      telefono: map['telefono'] as String?,
      puesto: map['puesto'] as String?,
      cuotaMinima: (map['cuota_minima'] as num?)?.toDouble() ?? 0,
        seguroLeyMonto:
          (map['seguro_ley_monto'] as num?)?.toDouble() ??
          (map['seguro_ley_pct'] as num?)?.toDouble() ??
          0,
      activo: (map['activo'] ?? 1) == 1,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'owner_id': ownerId,
      'nombre': nombre,
      'telefono': telefono,
      'puesto': puesto,
      'cuota_minima': cuotaMinima,
      'seguro_ley_monto': seguroLeyMonto,
      'seguro_ley_pct': seguroLeyMonto,
      'activo': activo ? 1 : 0,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}

class PayrollPeriod {
  final String id;
  final String ownerId;
  final String title;
  final DateTime startDate;
  final DateTime endDate;
  final PayrollPeriodStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const PayrollPeriod({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.createdAt,
    this.updatedAt,
  });

  bool get isOpen => status == PayrollPeriodStatus.open;

  factory PayrollPeriod.fromMap(Map<String, dynamic> map) {
    return PayrollPeriod(
      id: (map['id'] ?? '').toString(),
      ownerId: (map['owner_id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      startDate: DateTime.parse((map['start_date']).toString()),
      endDate: DateTime.parse((map['end_date']).toString()),
      status: PayrollPeriodStatusX.fromDb((map['status'] ?? 'OPEN').toString()),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'owner_id': ownerId,
      'title': title,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
      'status': status.dbValue,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}

class PayrollEmployeeConfig {
  final String id;
  final String ownerId;
  final String periodId;
  final String employeeId;
  final double baseSalary;
  final bool includeCommissions;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const PayrollEmployeeConfig({
    required this.id,
    required this.ownerId,
    required this.periodId,
    required this.employeeId,
    required this.baseSalary,
    required this.includeCommissions,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  factory PayrollEmployeeConfig.fromMap(Map<String, dynamic> map) {
    return PayrollEmployeeConfig(
      id: (map['id'] ?? '').toString(),
      ownerId: (map['owner_id'] ?? '').toString(),
      periodId: (map['period_id'] ?? '').toString(),
      employeeId: (map['employee_id'] ?? '').toString(),
      baseSalary: (map['base_salary'] as num?)?.toDouble() ?? 0,
      includeCommissions: (map['include_commissions'] ?? 0) == 1,
      notes: map['notes'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'owner_id': ownerId,
      'period_id': periodId,
      'employee_id': employeeId,
      'base_salary': baseSalary,
      'include_commissions': includeCommissions ? 1 : 0,
      'notes': notes,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}

class PayrollEntry {
  final String id;
  final String ownerId;
  final String periodId;
  final String employeeId;
  final DateTime date;
  final PayrollEntryType type;
  final String concept;
  final double amount;
  final double? cantidad;
  final DateTime? createdAt;

  const PayrollEntry({
    required this.id,
    required this.ownerId,
    required this.periodId,
    required this.employeeId,
    required this.date,
    required this.type,
    required this.concept,
    required this.amount,
    this.cantidad,
    this.createdAt,
  });

  factory PayrollEntry.fromMap(Map<String, dynamic> map) {
    return PayrollEntry(
      id: (map['id'] ?? '').toString(),
      ownerId: (map['owner_id'] ?? '').toString(),
      periodId: (map['period_id'] ?? '').toString(),
      employeeId: (map['employee_id'] ?? '').toString(),
      date: DateTime.parse((map['date']).toString()),
      type: PayrollEntryTypeX.fromDb((map['type'] ?? 'OTRO').toString()),
      concept: (map['concept'] ?? '').toString(),
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      cantidad: (map['cantidad'] as num?)?.toDouble(),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'owner_id': ownerId,
      'period_id': periodId,
      'employee_id': employeeId,
      'date': date.toIso8601String(),
      'type': type.dbValue,
      'concept': concept,
      'amount': amount,
      'cantidad': cantidad,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}

class PayrollTotals {
  final double baseSalary;
  final double commissions;
  final double bonuses;
  final double otherAdditions;
  final double absences;
  final double late;
  final double advances;
  final double otherDeductions;
  final double seguroLey;
  final double additions;
  final double deductions;
  final double total;

  const PayrollTotals({
    required this.baseSalary,
    this.commissions = 0,
    this.bonuses = 0,
    this.otherAdditions = 0,
    this.absences = 0,
    this.late = 0,
    this.advances = 0,
    this.otherDeductions = 0,
    this.seguroLey = 0,
    required this.additions,
    required this.deductions,
    required this.total,
  });
}

class PayrollHistoryItem {
  final String entryId;
  final String periodId;
  final String periodTitle;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String periodStatus;
  final double baseSalary;
  final double commissionFromSales;
  final double overtimeAmount;
  final double bonusesAmount;
  final double deductionsAmount;
  final double benefitsAmount;
  final double grossTotal;
  final double netTotal;

  const PayrollHistoryItem({
    required this.entryId,
    required this.periodId,
    required this.periodTitle,
    required this.periodStart,
    required this.periodEnd,
    required this.periodStatus,
    required this.baseSalary,
    required this.commissionFromSales,
    required this.overtimeAmount,
    required this.bonusesAmount,
    required this.deductionsAmount,
    required this.benefitsAmount,
    required this.grossTotal,
    required this.netTotal,
  });

  bool get isPaid => periodStatus.toUpperCase() == 'PAID';

  factory PayrollHistoryItem.fromMap(Map<String, dynamic> map) {
    return PayrollHistoryItem(
      entryId: (map['entry_id'] ?? '').toString(),
      periodId: (map['period_id'] ?? '').toString(),
      periodTitle: (map['period_title'] ?? '').toString(),
      periodStart: DateTime.parse((map['period_start']).toString()),
      periodEnd: DateTime.parse((map['period_end']).toString()),
      periodStatus: (map['period_status'] ?? 'DRAFT').toString(),
      baseSalary: (map['base_salary'] as num?)?.toDouble() ?? 0,
      commissionFromSales: (map['commission_from_sales'] as num?)?.toDouble() ?? 0,
      overtimeAmount: (map['overtime_amount'] as num?)?.toDouble() ?? 0,
      bonusesAmount: (map['bonuses_amount'] as num?)?.toDouble() ?? 0,
      deductionsAmount: (map['deductions_amount'] as num?)?.toDouble() ?? 0,
      benefitsAmount: (map['benefits_amount'] as num?)?.toDouble() ?? 0,
      grossTotal: (map['gross_total'] as num?)?.toDouble() ?? 0,
      netTotal: (map['net_total'] as num?)?.toDouble() ?? 0,
    );
  }
}
