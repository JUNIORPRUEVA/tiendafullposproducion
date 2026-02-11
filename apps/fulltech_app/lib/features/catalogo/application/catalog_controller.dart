import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/models/product_model.dart';
import '../data/catalog_repository.dart';

class CatalogState {
  final List<ProductModel> items;
  final bool loading;
  final String? error;
  final bool saving;
  final String? actionError;

  const CatalogState({
    this.items = const [],
    this.loading = false,
    this.error,
    this.saving = false,
    this.actionError,
  });

  CatalogState copyWith({
    List<ProductModel>? items,
    bool? loading,
    String? error,
    bool? saving,
    String? actionError,
    bool clearError = false,
  }) {
    return CatalogState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      saving: saving ?? this.saving,
      actionError: clearError ? null : (actionError ?? this.actionError),
    );
  }
}

final catalogControllerProvider = StateNotifierProvider<CatalogController, CatalogState>((ref) {
  return CatalogController(ref);
});

class CatalogController extends StateNotifier<CatalogState> {
  final Ref ref;
  CatalogController(this.ref) : super(const CatalogState()) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final repo = ref.read(catalogRepositoryProvider);
      final items = await repo.fetchProducts();
      state = state.copyWith(items: items, loading: false);
    } catch (e) {
      final message = e is ApiException ? e.message : 'No se pudieron cargar los productos';
      state = state.copyWith(loading: false, error: message);
    }
  }

  Future<void> create({
    required String nombre,
    required double precio,
    required double costo,
    required List<int> imageBytes,
    required String filename,
  }) async {
    state = state.copyWith(saving: true, actionError: null);
    try {
      final repo = ref.read(catalogRepositoryProvider);
      final path = await repo.uploadImage(bytes: imageBytes, filename: filename);
      final created = await repo.createProduct(nombre: nombre, precio: precio, costo: costo, fotoUrl: path);
      final updated = [created, ...state.items];
      state = state.copyWith(items: updated, saving: false);
    } catch (e) {
      final message = e is ApiException ? e.message : 'No se pudo crear el producto';
      state = state.copyWith(saving: false, actionError: message);
      rethrow;
    }
  }

  Future<void> update({
    required String id,
    required String nombre,
    required double precio,
    required double costo,
    List<int>? newImageBytes,
    String? newFilename,
  }) async {
    state = state.copyWith(saving: true, actionError: null);
    try {
      final repo = ref.read(catalogRepositoryProvider);
      String? fotoUrl;
      if (newImageBytes != null && newFilename != null) {
        fotoUrl = await repo.uploadImage(bytes: newImageBytes, filename: newFilename);
      }
      final updated = await repo.updateProduct(id: id, nombre: nombre, precio: precio, costo: costo, fotoUrl: fotoUrl);
      final list = state.items.map((p) => p.id == id ? updated : p).toList();
      state = state.copyWith(items: list, saving: false);
    } catch (e) {
      final message = e is ApiException ? e.message : 'No se pudo actualizar el producto';
      state = state.copyWith(saving: false, actionError: message);
      rethrow;
    }
  }

  Future<void> remove(String id) async {
    state = state.copyWith(saving: true, actionError: null);
    try {
      final repo = ref.read(catalogRepositoryProvider);
      await repo.deleteProduct(id);
      state = state.copyWith(items: state.items.where((p) => p.id != id).toList(), saving: false);
    } catch (e) {
      final message = e is ApiException ? e.message : 'No se pudo eliminar el producto';
      state = state.copyWith(saving: false, actionError: message);
      rethrow;
    }
  }
}
