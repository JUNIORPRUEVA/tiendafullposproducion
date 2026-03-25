import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/models/product_model.dart';
import '../../../features/catalogo/data/catalog_local_repository.dart';

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
      return CotizacionCatalogLocalDataSource(
        ref.watch(catalogLocalRepositoryProvider),
      );
    });

class CotizacionCatalogLocalDataSource {
  static const _dbName = 'cotizacion_catalog_cache.db';
  static const _dbVersion = 1;
  static const _tableMeta = 'cotizacion_catalog_meta';
  static const _metaSelectedCategory = 'selected_category';
  static const _metaSearchQuery = 'search_query';

  static CotizacionCatalogUiStateSnapshot? _memoryUiState;

  CotizacionCatalogLocalDataSource(this._catalogLocalRepository);

  final CatalogLocalRepository _catalogLocalRepository;

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
    final snapshot = await _catalogLocalRepository.readSnapshot();
    return CotizacionCatalogCacheSnapshot(
      items: snapshot.items,
      lastSyncedAt: snapshot.lastSyncedAt,
      catalogVersion: snapshot.catalogVersion,
    );
  }

  Future<void> saveSnapshot(
    List<ProductModel> items, {
    required DateTime syncedAt,
    required String catalogVersion,
  }) async {
    await _catalogLocalRepository.saveSnapshot(
      items,
      syncedAt: syncedAt,
      catalogVersion: catalogVersion,
    );
  }

  Future<CotizacionCatalogUiStateSnapshot> readUiState() async {
    final memoryUiState = _memoryUiState;
    if (memoryUiState != null) {
      return memoryUiState;
    }

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

    final snapshot = CotizacionCatalogUiStateSnapshot(
      selectedCategory: (selectedCategory == null || selectedCategory.isEmpty)
          ? null
          : selectedCategory,
      searchQuery: values[_metaSearchQuery] ?? '',
    );
    _memoryUiState = snapshot;
    return snapshot;
  }

  Future<void> saveUiState({
    String? selectedCategory,
    required String searchQuery,
  }) async {
    _memoryUiState = CotizacionCatalogUiStateSnapshot(
      selectedCategory: selectedCategory?.trim().isEmpty ?? true
          ? null
          : selectedCategory?.trim(),
      searchQuery: searchQuery.trim(),
    );

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
