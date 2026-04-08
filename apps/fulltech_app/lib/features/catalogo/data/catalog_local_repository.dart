import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/storage/resilient_local_database.dart';
import '../../../core/models/product_model.dart';

class CatalogLocalSnapshot {
  const CatalogLocalSnapshot({
    required this.items,
    this.lastSyncedAt,
    this.catalogVersion,
  });

  final List<ProductModel> items;
  final DateTime? lastSyncedAt;
  final String? catalogVersion;
}

final catalogLocalRepositoryProvider = Provider<CatalogLocalRepository>((ref) {
  return CatalogLocalRepository();
});

class CatalogLocalRepository {
  static const _dbName = 'fulltech_catalog_local.db';
  static const _dbVersion = 2;
  static const _tableProducts = 'catalog_products';
  static const _tableMeta = 'catalog_meta';
  static const _metaLastSyncedAt = 'last_synced_at';
  static const _metaCatalogVersion = 'catalog_version';

  Database? _database;
  CatalogLocalSnapshot? _memorySnapshot;

  Future<Database> get _db async {
    if (_database != null) return _database!;
    _database = await openResilientLocalDatabase(
      fileName: _dbName,
      version: _dbVersion,
      onCreate: (db, version) async => _createSchema(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        await _createSchema(db);
        if (oldVersion < 2) {
          await _addColumnIfMissing(
            db,
            tableName: _tableProducts,
            columnName: 'sync_version',
            definition: 'TEXT',
          );
          await _addColumnIfMissing(
            db,
            tableName: _tableProducts,
            columnName: 'is_active',
            definition: 'INTEGER NOT NULL DEFAULT 1',
          );
        }
      },
    );
    return _database!;
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableProducts (
        id TEXT PRIMARY KEY,
        position INTEGER NOT NULL,
        payload TEXT NOT NULL,
        updated_at TEXT,
        sync_version TEXT,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableMeta (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  Future<void> _addColumnIfMissing(
    DatabaseExecutor db, {
    required String tableName,
    required String columnName,
    required String definition,
  }) async {
    final columns = await db.rawQuery('PRAGMA table_info($tableName)');
    final alreadyExists = columns.any(
      (row) => (row['name'] ?? '').toString().trim() == columnName,
    );
    if (alreadyExists) {
      return;
    }
    await db.execute(
      'ALTER TABLE $tableName ADD COLUMN $columnName $definition',
    );
  }

  Future<CatalogLocalSnapshot> readSnapshot() async {
    final memorySnapshot = _memorySnapshot;
    if (memorySnapshot != null) {
      return memorySnapshot;
    }

    if (kIsWeb) {
      return const CatalogLocalSnapshot(items: []);
    }

    final db = await _db;
    final rows = await db.query(_tableProducts, orderBy: 'position ASC');
    final metaRows = await db.query(_tableMeta);
    final meta = {
      for (final row in metaRows)
        (row['key'] ?? '').toString(): row['value']?.toString(),
    };

    final snapshot = CatalogLocalSnapshot(
      items: rows
          .map((row) => (row['payload'] ?? '').toString())
          .where((payload) => payload.trim().isNotEmpty)
          .map((payload) => jsonDecode(payload))
          .whereType<Map>()
          .map(
            (payload) => ProductModel.fromJson(payload.cast<String, dynamic>()),
          )
          .toList(growable: false),
      lastSyncedAt: DateTime.tryParse(meta[_metaLastSyncedAt] ?? ''),
      catalogVersion: meta[_metaCatalogVersion],
    );
    _memorySnapshot = snapshot;
    return snapshot;
  }

  Future<void> saveSnapshot(
    List<ProductModel> items, {
    required DateTime syncedAt,
    required String catalogVersion,
  }) async {
    final normalizedItems = items.toList(growable: false);
    _memorySnapshot = CatalogLocalSnapshot(
      items: normalizedItems,
      lastSyncedAt: syncedAt,
      catalogVersion: catalogVersion,
    );

    if (kIsWeb) {
      return;
    }

    final db = await _db;
    await db.transaction((txn) async {
      if (normalizedItems.isEmpty) {
        await txn.delete(_tableProducts);
      } else {
        final ids = normalizedItems.map((item) => item.id).toList(growable: false);
        final placeholders = List.filled(ids.length, '?').join(', ');
        await txn.delete(
          _tableProducts,
          where: 'id NOT IN ($placeholders)',
          whereArgs: ids,
        );

        for (var index = 0; index < normalizedItems.length; index++) {
          final item = normalizedItems[index];
          await txn.insert(_tableProducts, {
            'id': item.id,
            'position': index,
            'payload': jsonEncode(item.toJson()),
            'updated_at': item.updatedAt?.toIso8601String(),
            'sync_version': catalogVersion,
            'is_active': item.activo ? 1 : 0,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      await _writeMeta(txn, _metaLastSyncedAt, syncedAt.toIso8601String());
      await _writeMeta(txn, _metaCatalogVersion, catalogVersion);
    });
  }

  Future<void> clearSnapshot() async {
    _memorySnapshot = const CatalogLocalSnapshot(items: []);
    if (kIsWeb) {
      return;
    }
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(_tableProducts);
      await _writeMeta(txn, _metaLastSyncedAt, null);
      await _writeMeta(txn, _metaCatalogVersion, null);
    });
  }

  Future<void> _writeMeta(Transaction txn, String key, String? value) async {
    await txn.insert(_tableMeta, {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}