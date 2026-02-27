import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../cotizacion_models.dart';

final cotizacionesLocalRepositoryProvider =
    Provider<CotizacionesLocalRepository>((ref) {
      return CotizacionesLocalRepository();
    });

class CotizacionesLocalRepository {
  static const _dbName = 'cotizaciones_local.db';
  static const _dbVersion = 1;
  static const _tableCotizaciones = 'cotizaciones';
  static const _tableItems = 'cotizacion_items';

  Database? _database;

  Future<Database> get _db async {
    if (_database != null) return _database!;
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    _database = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableCotizaciones (
            id TEXT PRIMARY KEY,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            customer_id TEXT,
            customer_name TEXT NOT NULL,
            customer_phone TEXT,
            note TEXT,
            include_itbis INTEGER NOT NULL DEFAULT 0,
            itbis_rate REAL NOT NULL DEFAULT 0.18,
            is_draft INTEGER NOT NULL DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE $_tableItems (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            cotizacion_id TEXT NOT NULL,
            product_id TEXT NOT NULL,
            nombre TEXT NOT NULL,
            image_url TEXT,
            unit_price REAL NOT NULL,
            qty REAL NOT NULL
          )
        ''');

        await db.execute(
          'CREATE INDEX idx_cotizacion_items_quote ON $_tableItems(cotizacion_id)',
        );
      },
    );
    return _database!;
  }

  Future<List<CotizacionModel>> listAll() async {
    final db = await _db;
    final rows = await db.query(
      _tableCotizaciones,
      where: 'is_draft = ?',
      whereArgs: [0],
      orderBy: 'created_at DESC',
    );

    final itemsByQuote = await _loadItemsGrouped(
      rows.map((row) => (row['id'] ?? '').toString()).toList(),
    );

    return rows
        .map(
          (row) => _toModel(
            row,
            itemsByQuote[(row['id'] ?? '').toString()] ?? const [],
          ),
        )
        .toList();
  }

  Future<void> upsert(CotizacionModel cotizacion) async {
    await _upsert(cotizacion, isDraft: false);
  }

  Future<void> saveDraft(CotizacionModel cotizacion) async {
    final db = await _db;
    await db.delete(_tableCotizaciones, where: 'is_draft = ?', whereArgs: [1]);
    await db.delete(
      _tableItems,
      where: 'cotizacion_id NOT IN (SELECT id FROM $_tableCotizaciones)',
    );
    await _upsert(cotizacion, isDraft: true);
  }

  Future<CotizacionModel?> getDraft() async {
    final db = await _db;
    final rows = await db.query(
      _tableCotizaciones,
      where: 'is_draft = ?',
      whereArgs: [1],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final row = rows.first;
    final quoteId = (row['id'] ?? '').toString();
    final itemRows = await db.query(
      _tableItems,
      where: 'cotizacion_id = ?',
      whereArgs: [quoteId],
      orderBy: 'id ASC',
    );

    return _toModel(row, itemRows);
  }

  Future<void> clearDraft() async {
    final db = await _db;
    final draftRows = await db.query(
      _tableCotizaciones,
      columns: ['id'],
      where: 'is_draft = ?',
      whereArgs: [1],
    );

    for (final row in draftRows) {
      final id = (row['id'] ?? '').toString();
      await db.delete(_tableItems, where: 'cotizacion_id = ?', whereArgs: [id]);
    }

    await db.delete(_tableCotizaciones, where: 'is_draft = ?', whereArgs: [1]);
  }

  Future<void> deleteById(String id) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(_tableItems, where: 'cotizacion_id = ?', whereArgs: [id]);
      await txn.delete(_tableCotizaciones, where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> _upsert(CotizacionModel cotizacion, {required bool isDraft}) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      await txn.insert(_tableCotizaciones, {
        'id': cotizacion.id,
        'created_at': cotizacion.createdAt.toIso8601String(),
        'updated_at': now,
        'customer_id': cotizacion.customerId,
        'customer_name': cotizacion.customerName,
        'customer_phone': cotizacion.customerPhone,
        'note': cotizacion.note,
        'include_itbis': cotizacion.includeItbis ? 1 : 0,
        'itbis_rate': cotizacion.itbisRate,
        'is_draft': isDraft ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await txn.delete(
        _tableItems,
        where: 'cotizacion_id = ?',
        whereArgs: [cotizacion.id],
      );

      for (final item in cotizacion.items) {
        await txn.insert(_tableItems, {
          'cotizacion_id': cotizacion.id,
          'product_id': item.productId,
          'nombre': item.nombre,
          'image_url': item.imageUrl,
          'unit_price': item.unitPrice,
          'qty': item.qty,
        });
      }
    });
  }

  Future<Map<String, List<Map<String, Object?>>>> _loadItemsGrouped(
    List<String> quoteIds,
  ) async {
    if (quoteIds.isEmpty) return {};

    final db = await _db;
    final placeholders = List.filled(quoteIds.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT * FROM $_tableItems WHERE cotizacion_id IN ($placeholders) ORDER BY id ASC',
      quoteIds,
    );

    final result = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      final id = (row['cotizacion_id'] ?? '').toString();
      result.putIfAbsent(id, () => <Map<String, Object?>>[]).add(row);
    }
    return result;
  }

  CotizacionModel _toModel(Map<String, Object?> row, List<Map<String, Object?>> itemRows) {
    return CotizacionModel(
      id: (row['id'] ?? '').toString(),
      createdAt: DateTime.tryParse((row['created_at'] ?? '').toString()) ??
          DateTime.now(),
      customerId: row['customer_id']?.toString(),
      customerName: (row['customer_name'] ?? '').toString(),
      customerPhone: row['customer_phone']?.toString(),
      note: (row['note'] ?? '').toString(),
      includeItbis: (row['include_itbis'] as num?)?.toInt() == 1,
      itbisRate: (row['itbis_rate'] as num?)?.toDouble() ?? 0.18,
      items: itemRows
          .map(
            (itemRow) => CotizacionItem(
              productId: (itemRow['product_id'] ?? '').toString(),
              nombre: (itemRow['nombre'] ?? '').toString(),
              imageUrl: itemRow['image_url']?.toString(),
              unitPrice: (itemRow['unit_price'] as num?)?.toDouble() ?? 0,
              qty: (itemRow['qty'] as num?)?.toDouble() ?? 0,
            ),
          )
          .toList(),
    );
  }
}
