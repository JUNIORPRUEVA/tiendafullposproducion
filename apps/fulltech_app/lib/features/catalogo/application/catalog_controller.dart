import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/models/product_model.dart';
import '../data/catalog_repository.dart';

class CatalogState {
  final List<ProductModel> items;
  final bool loading;
  final String? error;

  const CatalogState({
    this.items = const [],
    this.loading = false,
    this.error,
  });

  CatalogState copyWith({
    List<ProductModel>? items,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return CatalogState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
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
}
