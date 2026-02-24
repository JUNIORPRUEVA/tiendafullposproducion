import 'dart:math';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../nomina_models.dart';

class NominaDatabaseHelper {
  NominaDatabaseHelper._();

  static final NominaDatabaseHelper instance = NominaDatabaseHelper._();

  static const String _dbName = 'fulltech_nomina.db';
  static const int _dbVersion = 1;

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
    await _createIndexes(db);
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
    final config = await getEmployeeConfig(ownerId, periodId, employeeId);
    final entries = await listEntries(ownerId, periodId, employeeId);

    final base = config?.baseSalary ?? 0;
    double additions = 0;
    double deductions = 0;

    for (final item in entries) {
      if (item.amount >= 0) {
        additions += item.amount;
      } else {
        deductions += item.amount.abs();
      }
    }

    final total = base + additions - deductions;

    return PayrollTotals(
      baseSalary: base,
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
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT
        e.id AS entry_id,
        p.id AS period_id,
        p.title AS period_title,
        p.start_date AS period_start,
        p.end_date AS period_end,
        p.status AS period_status,
        COALESCE(e.base_salary, 0) AS base_salary,
        COALESCE(e.commission_from_sales, 0) AS commission_from_sales,
        COALESCE(e.overtime_amount, 0) AS overtime_amount,
        COALESCE(e.bonuses_amount, 0) AS bonuses_amount,
        COALESCE(e.deductions_amount, 0) AS deductions_amount,
        COALESCE(e.benefits_amount, 0) AS benefits_amount,
        COALESCE(e.gross_total, 0) AS gross_total,
        COALESCE(e.net_total, 0) AS net_total
      FROM payroll_entries e
      INNER JOIN payroll_periods p
        ON p.id = e.period_id AND p.owner_id = e.owner_id
      WHERE e.owner_id = ?
        AND e.employee_id = ?
      ORDER BY p.start_date DESC
      ''',
      [ownerId, employeeId],
    );
    return rows.map(PayrollHistoryItem.fromMap).toList();
  }
}
