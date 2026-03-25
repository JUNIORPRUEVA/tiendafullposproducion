import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/fulltech_cache_manager.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/models/product_model.dart';
import '../data/catalog_local_repository.dart';
import '../data/catalog_repository.dart';
import '../data/catalog_sync_utils.dart';

class CatalogState {
  final List<ProductModel> items;
  final bool loading;
  final bool refreshing;
  final String? error;
  final bool saving;
  final String? actionError;

  const CatalogState({
    this.items = const [],
    this.loading = false,
    this.refreshing = false,
    this.error,
    this.saving = false,
    this.actionError,
  });

  CatalogState copyWith({
    List<ProductModel>? items,
    bool? loading,
    bool? refreshing,
    String? error,
    bool? saving,
    String? actionError,
    bool clearError = false,
  }) {
    return CatalogState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      refreshing: refreshing ?? this.refreshing,
      error: clearError ? null : (error ?? this.error),
      saving: saving ?? this.saving,
      actionError: clearError ? null : (actionError ?? this.actionError),
    );
  }
}

final catalogControllerProvider =
    StateNotifierProvider<CatalogController, CatalogState>((ref) {
      return CatalogController(ref);
    });

class CatalogController extends StateNotifier<CatalogState> {
  final Ref ref;
  static const _silentRefreshMinInterval = Duration(seconds: 20);
  bool _remoteRefreshInFlight = false;
  DateTime? _lastSuccessfulRemoteSyncAt;

  CatalogController(this.ref) : super(const CatalogState());

  Future<CatalogLocalSnapshot> _loadFromLocal() {
    return ref.read(catalogLocalRepositoryProvider).readSnapshot();
  }

  Future<void> _saveToLocal(List<ProductModel> items, {DateTime? syncedAt}) {
    final catalogVersion = buildCatalogSyncVersion(items);
    return ref.read(catalogLocalRepositoryProvider).saveSnapshot(
      items,
      syncedAt: syncedAt ?? DateTime.now(),
      catalogVersion: catalogVersion,
    );
  }

  Future<void> load({bool silent = false, bool forceRemote = false}) async {
    if (silent && forceRemote && _remoteRefreshInFlight) return;
    if (silent &&
        forceRemote &&
        state.items.isNotEmpty &&
        _lastSuccessfulRemoteSyncAt != null &&
        DateTime.now().difference(_lastSuccessfulRemoteSyncAt!) <
            _silentRefreshMinInterval) {
      return;
    }
    if (silent && forceRemote) {
      _remoteRefreshInFlight = true;
    }

    final shouldShowLoading = !silent || state.items.isEmpty;

    if (shouldShowLoading && state.items.isEmpty) {
      final snapshot = await _loadFromLocal();
      if (snapshot.items.isNotEmpty) {
        _lastSuccessfulRemoteSyncAt ??= snapshot.lastSyncedAt;
        state = state.copyWith(
          items: snapshot.items,
          loading: false,
          refreshing: true,
          clearError: true,
        );
      } else {
        state = state.copyWith(
          loading: true,
          refreshing: false,
          clearError: true,
        );
      }
    } else if (shouldShowLoading) {
      state = state.copyWith(
        loading: false,
        refreshing: true,
        clearError: true,
      );
    } else {
      state = state.copyWith(clearError: true);
    }

    try {
      final repo = ref.read(catalogRepositoryProvider);
      final fetched = await repo.fetchProducts(
        forceRefresh: forceRemote,
        silent: silent,
      );
      final merged = mergeRecoveredCatalogImages(
        previousItems: state.items,
        fetchedItems: fetched,
      );
      final syncVersion = buildCatalogSyncVersion(merged);
      final items = applyCatalogSyncVersion(merged, syncVersion);
      state = state.copyWith(items: items, loading: false, refreshing: false);
      await _saveToLocal(items);
      Future<void>.microtask(
        () => FulltechImageCacheManager.warmImageUrls(
          items.map((item) => item.displayFotoUrl),
        ),
      );
      _lastSuccessfulRemoteSyncAt = DateTime.now();
    } catch (e) {
      final message = e is ApiException
          ? e.message
          : 'No se pudieron cargar los productos';
      // Keep cached/previous items (if any) so UI doesn't go blank.
      if (silent && state.items.isNotEmpty) return;
      state = state.copyWith(
        loading: false,
        refreshing: false,
        error: message,
      );
    } finally {
      if (silent && forceRemote) {
        _remoteRefreshInFlight = false;
      }
    }
  }

  Future<void> create({
    required String nombre,
    required double precio,
    required double costo,
    required List<int> imageBytes,
    required String filename,
    required String categoria,
  }) async {
    state = state.copyWith(saving: true, actionError: null);
    try {
      final repo = ref.read(catalogRepositoryProvider);
      final path = await repo.uploadImage(
        bytes: imageBytes,
        filename: filename,
      );
      final created = await repo.createProduct(
        nombre: nombre,
        precio: precio,
        costo: costo,
        fotoUrl: path,
        categoria: categoria,
      );
      final updated = [created, ...state.items];
      state = state.copyWith(items: updated, saving: false);
      await _saveToLocal(updated);
      _lastSuccessfulRemoteSyncAt = DateTime.now();
    } catch (e) {
      final message = e is ApiException
          ? e.message
          : 'No se pudo crear el producto';
      state = state.copyWith(saving: false, actionError: message);
      rethrow;
    }
  }

  Future<void> update({
    required String id,
    required String nombre,
    required double precio,
    required double costo,
    required String categoria,
    List<int>? newImageBytes,
    String? newFilename,
  }) async {
    state = state.copyWith(saving: true, actionError: null);
    try {
      final repo = ref.read(catalogRepositoryProvider);
      String? fotoUrl;
      if (newImageBytes != null && newFilename != null) {
        fotoUrl = await repo.uploadImage(
          bytes: newImageBytes,
          filename: newFilename,
        );
      }
      final updated = await repo.updateProduct(
        id: id,
        nombre: nombre,
        precio: precio,
        costo: costo,
        fotoUrl: fotoUrl,
        categoria: categoria,
      );
      final list = state.items.map((p) => p.id == id ? updated : p).toList();
      state = state.copyWith(items: list, saving: false);
      await _saveToLocal(list);
      _lastSuccessfulRemoteSyncAt = DateTime.now();
    } catch (e) {
      final message = e is ApiException
          ? e.message
          : 'No se pudo actualizar el producto';
      state = state.copyWith(saving: false, actionError: message);
      rethrow;
    }
  }

  Future<void> remove(String id) async {
    state = state.copyWith(saving: true, actionError: null);
    try {
      final repo = ref.read(catalogRepositoryProvider);
      await repo.deleteProduct(id);
      final list = state.items.where((p) => p.id != id).toList();
      state = state.copyWith(items: list, saving: false);
      await _saveToLocal(list);
      _lastSuccessfulRemoteSyncAt = DateTime.now();
    } catch (e) {
      final message = e is ApiException
          ? e.message
          : 'No se pudo eliminar el producto';
      state = state.copyWith(saving: false, actionError: message);
      rethrow;
    }
  }
}
