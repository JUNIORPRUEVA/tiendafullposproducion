import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/models/product_model.dart';

class CotizacionCatalogCacheSnapshot {
  const CotizacionCatalogCacheSnapshot({
    required this.items,
    this.lastSyncedAt,
    this.catalogVersion,
  });

  final List<ProductModel> items;
  final DateTime? lastSyncedAt;
  final String? catalogVersion;
}

class CotizacionCatalogUiStateSnapshot {
  const CotizacionCatalogUiStateSnapshot({
    this.selectedCategory,
    this.searchQuery = '',
  });

  final String? selectedCategory;
  final String searchQuery;
}

final cotizacionCatalogLocalDataSourceProvider =
    Provider<CotizacionCatalogLocalDataSource>((ref) {
      return CotizacionCatalogLocalDataSource();
    });

class CotizacionCatalogLocalDataSource {
  static const _dbName = 'cotizacion_catalog_cache.db';
  static const _dbVersion = 1;
  static const _tableProducts = 'cotizacion_catalog_products';
  static const _tableMeta = 'cotizacion_catalog_meta';
  static const _metaLastSyncedAt = 'last_synced_at';
  static const _metaCatalogVersion = 'catalog_version';
  static const _metaSelectedCategory = 'selected_category';
  static const _metaSearchQuery = 'search_query';

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

  Future<CotizacionCatalogCacheSnapshot> readSnapshot() async {
    final db = await _db;
    final rows = await db.query(_tableProducts, orderBy: 'position ASC');
    final metaRows = await db.query(_tableMeta);
    final meta = {
      for (final row in metaRows)
        (row['key'] ?? '').toString(): row['value']?.toString(),
    };

    final items = rows
        .map((row) => (row['payload'] ?? '').toString())
        .where((payload) => payload.trim().isNotEmpty)
        .map((payload) => jsonDecode(payload))
        .whereType<Map>()
        .map(
          (payload) => ProductModel.fromJson(payload.cast<String, dynamic>()),
        )
        .toList(growable: false);

    return CotizacionCatalogCacheSnapshot(
      items: items,
      lastSyncedAt: DateTime.tryParse(meta[_metaLastSyncedAt] ?? ''),
      catalogVersion: meta[_metaCatalogVersion],
    );
  }

  Future<void> saveSnapshot(
    List<ProductModel> items, {
    required DateTime syncedAt,
    required String catalogVersion,
  }) async {
    final db = await _db;

    await db.transaction((txn) async {
      if (items.isEmpty) {
        await txn.delete(_tableProducts);
      } else {
        final ids = items.map((item) => item.id).toList(growable: false);
        final placeholders = List.filled(ids.length, '?').join(', ');
        await txn.delete(
          _tableProducts,
          where: 'id NOT IN ($placeholders)',
          whereArgs: ids,
        );

        for (var index = 0; index < items.length; index++) {
          final item = items[index];
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

  Future<CotizacionCatalogUiStateSnapshot> readUiState() async {
    final db = await _db;
    final rows = await db.query(
      _tableMeta,
      where: 'key IN (?, ?)',
      whereArgs: [_metaSelectedCategory, _metaSearchQuery],
    );
    final values = {
      for (final row in rows)
        (row['key'] ?? '').toString(): row['value']?.toString(),
    };
    final selectedCategory = values[_metaSelectedCategory]?.trim();

    return CotizacionCatalogUiStateSnapshot(
      selectedCategory: (selectedCategory == null || selectedCategory.isEmpty)
          ? null
          : selectedCategory,
      searchQuery: values[_metaSearchQuery] ?? '',
    );
  }

  Future<void> saveUiState({
    String? selectedCategory,
    required String searchQuery,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      await _writeMeta(txn, _metaSelectedCategory, selectedCategory?.trim());
      await _writeMeta(txn, _metaSearchQuery, searchQuery.trim());
    });
  }

  Future<void> _writeMeta(Transaction txn, String key, String? value) async {
    await txn.insert(_tableMeta, {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
