import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

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
  static const _dbVersion = 1;
  static const _tableProducts = 'catalog_products';
  static const _tableMeta = 'catalog_meta';
  static const _metaLastSyncedAt = 'last_synced_at';
  static const _metaCatalogVersion = 'catalog_version';

  Database? _database;
  CatalogLocalSnapshot? _memorySnapshot;

  Future<Database> get _db async {
    if (_database != null) return _database!;
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    _database = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableProducts (
            id TEXT PRIMARY KEY,
            position INTEGER NOT NULL,
            payload TEXT NOT NULL,
            updated_at TEXT,
            sync_version TEXT,
            is_active INTEGER NOT NULL DEFAULT 1
          )
        ''');
        await db.execute('''
          CREATE TABLE $_tableMeta (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
      },
    );
    return _database!;
  }

  Future<CatalogLocalSnapshot> readSnapshot() async {
    final memorySnapshot = _memorySnapshot;
    if (memorySnapshot != null) {
      return memorySnapshot;
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