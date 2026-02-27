import 'dart:math';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../nomina_models.dart';

class NominaDatabaseHelper {
  NominaDatabaseHelper._();

  static final NominaDatabaseHelper instance = NominaDatabaseHelper._();

  static const String _dbName = 'fulltech_nomina.db';
  static const int _dbVersion = 3;

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static String ownerIdOrDefault(String? ownerId) {
    final value = (ownerId ?? '').trim();
    return value.isEmpty ? 'default_owner' : value;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final fullPath = path.join(dbPath, _dbName);
    return openDatabase(
      fullPath,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE employees_payroll (
        id TEXT PRIMARY KEY,
        owner_id TEXT NOT NULL,
        nombre TEXT NOT NULL,
        telefono TEXT,
        puesto TEXT,
        cuota_minima REAL NOT NULL DEFAULT 0,
        seguro_ley_pct REAL NOT NULL DEFAULT 0,
        activo INTEGER NOT NULL DEFAULT 1,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE payroll_periods (
        id TEXT PRIMARY KEY,
        owner_id TEXT NOT NULL,
        title TEXT NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE payroll_employee_config (
        id TEXT PRIMARY KEY,
        owner_id TEXT NOT NULL,
        period_id TEXT NOT NULL,
        employee_id TEXT NOT NULL,
        base_salary REAL NOT NULL,
        include_commissions INTEGER NOT NULL DEFAULT 0,
        notes TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE payroll_entries (
        id TEXT PRIMARY KEY,
        owner_id TEXT NOT NULL,
        period_id TEXT NOT NULL,
        employee_id TEXT NOT NULL,
        date TEXT NOT NULL,
        type TEXT NOT NULL,
        concept TEXT NOT NULL,
        amount REAL NOT NULL,
        cantidad REAL,
        created_at TEXT
      )
    ''');

    await _createIndexes(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE employees_payroll ADD COLUMN cuota_minima REAL NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE employees_payroll ADD COLUMN seguro_ley_pct REAL NOT NULL DEFAULT 0',
      );
    }
    await _createIndexes(db);
  }

  DateTime _dateWithClampedDay(int year, int month, int day) {
    final lastDay = DateTime(year, month + 1, 0).day;
    final safeDay = day > lastDay ? lastDay : day;
    return DateTime(year, month, safeDay);
  }

  DateTime _periodStartFor(DateTime date) {
    if (date.day >= 15 && date.day <= 29) {
      return DateTime(date.year, date.month, 15);
    }

    if (date.day >= 30) {
      return _dateWithClampedDay(date.year, date.month, 30);
    }

    final prevMonth = DateTime(date.year, date.month - 1, 1);
    return _dateWithClampedDay(prevMonth.year, prevMonth.month, 30);
  }

  DateTime _periodEndFor(DateTime date) {
    if (date.day >= 15 && date.day <= 29) {
      return _dateWithClampedDay(date.year, date.month, 29);
    }

    if (date.day >= 30) {
      return DateTime(date.year, date.month + 1, 14);
    }

    return DateTime(date.year, date.month, 14);
  }

  String _periodTitle(DateTime date) {
    final start = _periodStartFor(date);
    final end = _periodEndFor(date);
    final quincenaNumber = end.day <= 14 ? 1 : 2;
    return 'Quincena $quincenaNumber · ${start.day.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}/${end.month.toString().padLeft(2, '0')}/${end.year}';
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_emp_payroll_owner ON employees_payroll(owner_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_periods_owner ON payroll_periods(owner_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cfg_owner ON payroll_employee_config(owner_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_entries_owner ON payroll_entries(owner_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cfg_period_employee ON payroll_employee_config(period_id, employee_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_entries_period_employee ON payroll_entries(period_id, employee_id)',
    );
  }

  String _id(String prefix) {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final random = Random().nextInt(1000000);
    return '$prefix$stamp$random';
  }

  Future<List<PayrollPeriod>> listPeriods(String ownerId) async {
    final db = await database;
    final rows = await db.query(
      'payroll_periods',
      where: 'owner_id = ?',
      whereArgs: [ownerId],
      orderBy: 'start_date DESC',
    );
    return rows.map(PayrollPeriod.fromMap).toList();
  }

  Future<PayrollPeriod?> getPeriodById(String ownerId, String periodId) async {
    final db = await database;
    final rows = await db.query(
      'payroll_periods',
      where: 'owner_id = ? AND id = ?',
      whereArgs: [ownerId, periodId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PayrollPeriod.fromMap(rows.first);
  }

  Future<bool> hasOverlappingOpenPeriod(
    String ownerId,
    DateTime start,
    DateTime end,
  ) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT id FROM payroll_periods
      WHERE owner_id = ?
        AND status = 'OPEN'
        AND DATE(start_date) <= DATE(?)
        AND DATE(end_date) >= DATE(?)
      LIMIT 1
      ''',
      [ownerId, end.toIso8601String(), start.toIso8601String()],
    );
    return rows.isNotEmpty;
  }

  Future<PayrollPeriod> createPeriod(
    String ownerId,
    DateTime start,
    DateTime end,
    String title,
  ) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final period = PayrollPeriod(
      id: _id('pr_'),
      ownerId: ownerId,
      title: title,
      startDate: start,
      endDate: end,
      status: PayrollPeriodStatus.open,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await db.insert('payroll_periods', {
      ...period.toMap(),
      'created_at': now,
      'updated_at': now,
    });

    return period;
  }

  Future<PayrollPeriod> ensureCurrentOpenPeriod(String ownerId) async {
    final db = await database;
    final nowDate = DateTime.now();
    final expectedStart = _periodStartFor(nowDate);
    final expectedEnd = _periodEndFor(nowDate);

    final existing = await db.query(
      'payroll_periods',
      where: 'owner_id = ? AND status = ?',
      whereArgs: [ownerId, PayrollPeriodStatus.open.dbValue],
      orderBy: 'start_date DESC',
    );

    for (final row in existing) {
      final period = PayrollPeriod.fromMap(row);
      final sameRange =
          period.startDate.year == expectedStart.year &&
          period.startDate.month == expectedStart.month &&
          period.startDate.day == expectedStart.day &&
          period.endDate.year == expectedEnd.year &&
          period.endDate.month == expectedEnd.month &&
          period.endDate.day == expectedEnd.day;

      if (sameRange) {
        return period;
      }
    }

    await db.update(
      'payroll_periods',
      {
        'status': PayrollPeriodStatus.closed.dbValue,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'owner_id = ? AND status = ?',
      whereArgs: [ownerId, PayrollPeriodStatus.open.dbValue],
    );

    return createPeriod(
      ownerId,
      expectedStart,
      expectedEnd,
      _periodTitle(nowDate),
    );
  }

  Future<PayrollPeriod> createNextOpenPeriod(
    String ownerId,
    PayrollPeriod closed,
  ) async {
    final nextBase = closed.endDate.add(const Duration(days: 1));
    final start = _periodStartFor(nextBase);
    final end = _periodEndFor(nextBase);
    return createPeriod(ownerId, start, end, _periodTitle(nextBase));
  }

  Future<void> closePeriod(String ownerId, String periodId) async {
    final db = await database;
    await db.update(
      'payroll_periods',
      {
        'status': PayrollPeriodStatus.closed.dbValue,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'owner_id = ? AND id = ?',
      whereArgs: [ownerId, periodId],
    );
  }

  Future<List<PayrollEmployee>> listEmployees(
    String ownerId, {
    bool activeOnly = true,
  }) async {
    final db = await database;
    final whereParts = ['owner_id = ?'];
    final args = <Object?>[ownerId];
    if (activeOnly) {
      whereParts.add('activo = 1');
    }
    final rows = await db.query(
      'employees_payroll',
      where: whereParts.join(' AND '),
      whereArgs: args,
      orderBy: 'nombre ASC',
    );
    return rows.map(PayrollEmployee.fromMap).toList();
  }

  Future<PayrollEmployee?> getEmployeeById(
    String ownerId,
    String employeeId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'employees_payroll',
      where: 'owner_id = ? AND id = ?',
      whereArgs: [ownerId, employeeId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PayrollEmployee.fromMap(rows.first);
  }

  Future<double> getEmployeeCuotaMinimaForUser({
    required String ownerId,
    required String userId,
    required String userName,
  }) async {
    final db = await database;

    final byId = await db.query(
      'employees_payroll',
      columns: const ['cuota_minima'],
      where: 'owner_id = ? AND id = ? AND activo = 1',
      whereArgs: [ownerId, userId],
      limit: 1,
    );
    if (byId.isNotEmpty) {
      return (byId.first['cuota_minima'] as num?)?.toDouble() ?? 0;
    }

    final trimmedName = userName.trim();
    if (trimmedName.isNotEmpty) {
      final byName = await db.query(
        'employees_payroll',
        columns: const ['cuota_minima'],
        where: 'owner_id = ? AND nombre = ? AND activo = 1',
        whereArgs: [ownerId, trimmedName],
        limit: 1,
      );
      if (byName.isNotEmpty) {
        return (byName.first['cuota_minima'] as num?)?.toDouble() ?? 0;
      }
    }

    return 0;
  }

  Future<PayrollEmployee> upsertEmployee(
    String ownerId,
    PayrollEmployee employee,
  ) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    if (employee.id.isEmpty) {
      final created = employee.copyWith(
        id: _id('emp_'),
        ownerId: ownerId,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await db.insert('employees_payroll', {
        ...created.toMap(),
        'created_at': now,
        'updated_at': now,
      });
      return created;
    }

    final existingRow = await db.query(
      'employees_payroll',
      columns: const ['id'],
      where: 'owner_id = ? AND id = ?',
      whereArgs: [ownerId, employee.id],
      limit: 1,
    );

    if (existingRow.isEmpty) {
      final createdWithProvidedId = employee.copyWith(
        ownerId: ownerId,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await db.insert('employees_payroll', {
        ...createdWithProvidedId.toMap(),
        'created_at': now,
        'updated_at': now,
      });
      return createdWithProvidedId;
    }

    final updated = employee.copyWith(updatedAt: DateTime.now());
    await db.update(
      'employees_payroll',
      {...updated.toMap(), 'updated_at': now},
      where: 'owner_id = ? AND id = ?',
      whereArgs: [ownerId, employee.id],
    );
    return updated;
  }

  Future<PayrollEmployeeConfig?> getEmployeeConfig(
    String ownerId,
    String periodId,
    String employeeId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'payroll_employee_config',
      where: 'owner_id = ? AND period_id = ? AND employee_id = ?',
      whereArgs: [ownerId, periodId, employeeId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PayrollEmployeeConfig.fromMap(rows.first);
  }

  Future<PayrollEmployeeConfig> upsertEmployeeConfig({
    required String ownerId,
    required String periodId,
    required String employeeId,
    required double baseSalary,
    required bool includeCommissions,
    String? notes,
  }) async {
    final db = await database;
    final existing = await getEmployeeConfig(ownerId, periodId, employeeId);
    final now = DateTime.now().toIso8601String();

    if (existing == null) {
      final config = PayrollEmployeeConfig(
        id: _id('cfg_'),
        ownerId: ownerId,
        periodId: periodId,
        employeeId: employeeId,
        baseSalary: baseSalary,
        includeCommissions: includeCommissions,
        notes: notes,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await db.insert('payroll_employee_config', {
        ...config.toMap(),
        'created_at': now,
        'updated_at': now,
      });
      return config;
    }

    final updated = PayrollEmployeeConfig(
      id: existing.id,
      ownerId: ownerId,
      periodId: periodId,
      employeeId: employeeId,
      baseSalary: baseSalary,
      includeCommissions: includeCommissions,
      notes: notes,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
    );

    await db.update(
      'payroll_employee_config',
      {...updated.toMap(), 'updated_at': now},
      where: 'owner_id = ? AND id = ?',
      whereArgs: [ownerId, existing.id],
    );

    return updated;
  }

  Future<List<PayrollEntry>> listEntries(
    String ownerId,
    String periodId,
    String employeeId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'payroll_entries',
      where: 'owner_id = ? AND period_id = ? AND employee_id = ?',
      whereArgs: [ownerId, periodId, employeeId],
      orderBy: 'date DESC, created_at DESC',
    );
    return rows.map(PayrollEntry.fromMap).toList();
  }

  Future<PayrollEntry> addEntry(String ownerId, PayrollEntry entry) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final created = PayrollEntry(
      id: entry.id.isEmpty ? _id('ent_') : entry.id,
      ownerId: ownerId,
      periodId: entry.periodId,
      employeeId: entry.employeeId,
      date: entry.date,
      type: entry.type,
      concept: entry.concept,
      amount: entry.amount,
      cantidad: entry.cantidad,
      createdAt: DateTime.now(),
    );
    await db.insert('payroll_entries', {...created.toMap(), 'created_at': now});
    return created;
  }

  Future<void> deleteEntry(String ownerId, String entryId) async {
    final db = await database;
    await db.delete(
      'payroll_entries',
      where: 'owner_id = ? AND id = ?',
      whereArgs: [ownerId, entryId],
    );
  }

  Future<PayrollTotals> computeTotals(
    String ownerId,
    String periodId,
    String employeeId,
  ) async {
    final employee = await getEmployeeById(ownerId, employeeId);
    final config = await getEmployeeConfig(ownerId, periodId, employeeId);
    final entries = await listEntries(ownerId, periodId, employeeId);

    final base = config?.baseSalary ?? 0;
    double commissions = 0;
    double bonuses = 0;
    double otherAdditions = 0;
    double absences = 0;
    double late = 0;
    double advances = 0;
    double otherDeductions = 0;

    for (final item in entries) {
      final amount = item.amount;
      switch (item.type) {
        case PayrollEntryType.comisionServicio:
        case PayrollEntryType.comisionVentas:
          if (amount >= 0) commissions += amount;
          break;
        case PayrollEntryType.bonificacion:
        case PayrollEntryType.pagoCombustible:
          if (amount >= 0) bonuses += amount;
          break;
        case PayrollEntryType.ausencia:
          absences += amount.abs();
          break;
        case PayrollEntryType.tarde:
          late += amount.abs();
          break;
        case PayrollEntryType.adelanto:
          advances += amount.abs();
          break;
        case PayrollEntryType.descuento:
          otherDeductions += amount.abs();
          break;
        case PayrollEntryType.otro:
          if (amount >= 0) {
            otherAdditions += amount;
          } else {
            otherDeductions += amount.abs();
          }
          break;
      }
    }

    final seguroLey = (employee?.seguroLeyMonto ?? 0)
        .clamp(0, double.infinity)
        .toDouble();

    final additions = commissions + bonuses + otherAdditions;
    final deductions = absences + late + advances + otherDeductions + seguroLey;

    final total = base + additions - deductions;

    return PayrollTotals(
      baseSalary: base,
      commissions: commissions,
      bonuses: bonuses,
      otherAdditions: otherAdditions,
      absences: absences,
      late: late,
      advances: advances,
      otherDeductions: otherDeductions,
      seguroLey: seguroLey,
      additions: additions,
      deductions: deductions,
      total: total,
    );
  }

  Future<double> computePeriodTotalAllEmployees(
    String ownerId,
    String periodId,
  ) async {
    final employees = await listEmployees(ownerId);
    double total = 0;
    for (final emp in employees) {
      final t = await computeTotals(ownerId, periodId, emp.id);
      total += t.total;
    }
    return total;
  }

  Future<List<PayrollHistoryItem>> listPayrollHistoryByEmployee(
    String ownerId,
    String employeeId,
  ) async {
    final periods = await listPeriods(ownerId);
    final history = <PayrollHistoryItem>[];

    for (final period in periods) {
      final entries = await listEntries(ownerId, period.id, employeeId);
      final config = await getEmployeeConfig(ownerId, period.id, employeeId);
      final employee = await getEmployeeById(ownerId, employeeId);

      final hasData = config != null || entries.isNotEmpty;
      if (!hasData) continue;

      final baseSalary = config?.baseSalary ?? 0;
      final seguroLey = (employee?.seguroLeyMonto ?? 0).clamp(
        0,
        double.infinity,
      );

      double commissionFromSales = 0;
      double overtimeAmount = 0;
      double bonusesAmount = 0;
      double deductionsAmount = 0;
      double benefitsAmount = 0;

      for (final entry in entries) {
        final amount = entry.amount;
        switch (entry.type) {
          case PayrollEntryType.comisionServicio:
          case PayrollEntryType.comisionVentas:
            commissionFromSales += amount;
            break;
          case PayrollEntryType.bonificacion:
          case PayrollEntryType.pagoCombustible:
            bonusesAmount += amount;
            break;
          case PayrollEntryType.ausencia:
          case PayrollEntryType.tarde:
          case PayrollEntryType.adelanto:
          case PayrollEntryType.descuento:
            deductionsAmount += amount.abs();
            break;
          case PayrollEntryType.otro:
            if (amount >= 0) {
              benefitsAmount += amount;
            } else {
              deductionsAmount += amount.abs();
            }
            break;
        }
      }

      final additions =
          commissionFromSales + overtimeAmount + bonusesAmount + benefitsAmount;
      final grossTotal = baseSalary + additions;
      final totalDeductions = deductionsAmount + seguroLey;
      final netTotal = grossTotal - totalDeductions;

      history.add(
        PayrollHistoryItem(
          entryId: entries.isNotEmpty
              ? entries.first.id
              : 'period_${period.id}',
          periodId: period.id,
          periodTitle: period.title,
          periodStart: period.startDate,
          periodEnd: period.endDate,
          periodStatus: period.status.dbValue,
          baseSalary: baseSalary,
          commissionFromSales: commissionFromSales,
          overtimeAmount: overtimeAmount,
          bonusesAmount: bonusesAmount,
          deductionsAmount: totalDeductions,
          benefitsAmount: benefitsAmount,
          grossTotal: grossTotal,
          netTotal: netTotal,
        ),
      );
    }

    return history;
  }

  Future<List<PayrollHistoryItem>> listPayrollHistoryByEmployeeAnyOwner(
    String employeeId,
  ) async {
    final db = await database;
    final ownerRows = await db.rawQuery(
      '''
      SELECT owner_id FROM employees_payroll WHERE id = ?
      UNION
      SELECT owner_id FROM payroll_employee_config WHERE employee_id = ?
      UNION
      SELECT owner_id FROM payroll_entries WHERE employee_id = ?
      ''',
      [employeeId, employeeId, employeeId],
    );

    final ownerIds = ownerRows
        .map((row) => (row['owner_id'] ?? '').toString())
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .toList();

    if (ownerIds.isEmpty) return const [];

    final all = <PayrollHistoryItem>[];
    for (final ownerId in ownerIds) {
      final rows = await listPayrollHistoryByEmployee(ownerId, employeeId);
      all.addAll(rows);
    }

    all.sort((a, b) => b.periodEnd.compareTo(a.periodEnd));
    return all;
  }
}
