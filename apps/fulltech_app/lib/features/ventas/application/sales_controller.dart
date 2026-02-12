import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/models/client_model.dart';
import '../../../core/models/product_model.dart';
import '../../../core/models/sale_model.dart';
import '../../catalogo/data/catalog_repository.dart';
import '../data/sales_repository.dart';

const saleStatusDraft = 'DRAFT';
const saleStatusConfirmed = 'CONFIRMED';
const saleStatusCancelled = 'CANCELLED';

class SaleItemInput {
  final String id;
  final ProductModel product;
  final int qty;
  final double price;

  const SaleItemInput({required this.id, required this.product, required this.qty, required this.price});

  double get lineTotal => qty * price;
  double get lineCost => qty * product.costo;
  double get lineProfit => lineTotal - lineCost;

  SaleItemInput copyWith({int? qty, double? price}) => SaleItemInput(
        id: id,
        product: product,
        qty: qty ?? this.qty,
        price: price ?? this.price,
      );
}

class SalesBuilderState {
  final List<ProductModel> products;
  final List<ClientModel> clients;
  final List<SaleItemInput> items;
  final ClientModel? selectedClient;
  final String note;
  final String status;
  final bool loading;
  final bool saving;
  final String? error;
  final SaleModel? lastSaved;

  const SalesBuilderState({
    this.products = const [],
    this.clients = const [],
    this.items = const [],
    this.selectedClient,
    this.note = '',
    this.status = saleStatusDraft,
    this.loading = false,
    this.saving = false,
    this.error,
    this.lastSaved,
  });

  SalesBuilderState copyWith({
    List<ProductModel>? products,
    List<ClientModel>? clients,
    List<SaleItemInput>? items,
    ClientModel? selectedClient,
    bool clearClient = false,
    String? note,
    String? status,
    bool? loading,
    bool? saving,
    String? error,
    bool clearError = false,
    SaleModel? lastSaved,
    bool clearLastSaved = false,
  }) {
    return SalesBuilderState(
      products: products ?? this.products,
      clients: clients ?? this.clients,
      items: items ?? this.items,
      selectedClient: clearClient ? null : (selectedClient ?? this.selectedClient),
      note: note ?? this.note,
      status: status ?? this.status,
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      error: clearError ? null : (error ?? this.error),
      lastSaved: clearLastSaved ? null : (lastSaved ?? this.lastSaved),
    );
  }

  double get subtotal => items.fold(0, (sum, i) => sum + i.lineTotal);
  double get totalCost => items.fold(0, (sum, i) => sum + i.lineCost);
  double get profit => subtotal - totalCost;
  double get commission => profit > 0 ? profit * 0.1 : 0;
}

final salesBuilderProvider = StateNotifierProvider.autoDispose<SalesBuilderController, SalesBuilderState>((ref) {
  return SalesBuilderController(ref);
});

class SalesBuilderController extends StateNotifier<SalesBuilderState> {
  final Ref ref;
  SalesBuilderController(this.ref) : super(const SalesBuilderState()) {
    _loadCatalog();
  }

  Future<void> refresh() => _loadCatalog();

  Future<void> _loadCatalog() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final products = await ref.read(catalogRepositoryProvider).fetchProducts();
      final clients = await ref.read(salesRepositoryProvider).fetchClients(pageSize: 50);
      state = state.copyWith(products: products, clients: clients, loading: false);
    } catch (e) {
      final msg = e is ApiException ? e.message : 'No se pudo cargar catálogo/clientes';
      state = state.copyWith(loading: false, error: msg);
    }
  }

  void selectClient(ClientModel? client) {
    state = state.copyWith(selectedClient: client);
  }

  void addClient(ClientModel client) {
    state = state.copyWith(clients: [...state.clients, client]);
  }

  void updateNote(String note) {
    state = state.copyWith(note: note);
  }

  void setStatus(String status) {
    state = state.copyWith(status: status);
  }

  void addItem(ProductModel product, {int qty = 1, double? price}) {
    final item = SaleItemInput(
      id: '${product.id}-${DateTime.now().microsecondsSinceEpoch}',
      product: product,
      qty: qty,
      price: price ?? product.precio,
    );
    state = state.copyWith(items: [...state.items, item], clearError: true, clearLastSaved: true);
  }

  void updateItem(String id, {int? qty, double? price}) {
    final updated = state.items.map((i) => i.id == id ? i.copyWith(qty: qty, price: price) : i).toList();
    state = state.copyWith(items: updated, clearLastSaved: true);
  }

  void removeItem(String id) {
    state = state.copyWith(items: state.items.where((i) => i.id != id).toList(), clearLastSaved: true);
  }

  Future<SaleModel> save({required bool confirm}) async {
    if (state.items.isEmpty) {
      throw ApiException('Agrega al menos un producto');
    }
    state = state.copyWith(saving: true, clearError: true);
    try {
      final repo = ref.read(salesRepositoryProvider);
      final sale = await repo.createSale(
        clientId: state.selectedClient?.id,
        note: state.note.isEmpty ? null : state.note,
        status: confirm ? saleStatusConfirmed : saleStatusDraft,
        items: state.items
            .map((i) => {
                  'productId': i.product.id,
                  'qty': i.qty,
                  'unitPriceSold': i.price,
                })
            .toList(),
      );
      state = state.copyWith(
        saving: false,
        lastSaved: sale,
        items: const [],
        note: '',
        status: saleStatusDraft,
        clearClient: true,
      );
      return sale;
    } catch (e) {
      final msg = e is ApiException ? e.message : 'No se pudo guardar la venta';
      state = state.copyWith(saving: false, error: msg);
      rethrow;
    }
  }
}

class SalesHistoryState {
  final List<SaleModel> items;
  final bool loading;
  final String? error;
  final Map<String, dynamic> summary;
  final DateTime? from;
  final DateTime? to;
  final String? status;

  const SalesHistoryState({
    this.items = const [],
    this.loading = false,
    this.error,
    this.summary = const {},
    this.from,
    this.to,
    this.status,
  });

  SalesHistoryState copyWith({
    List<SaleModel>? items,
    bool? loading,
    String? error,
    bool clearError = false,
    Map<String, dynamic>? summary,
    DateTime? from,
    DateTime? to,
    String? status,
  }) {
    return SalesHistoryState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      summary: summary ?? this.summary,
      from: from ?? this.from,
      to: to ?? this.to,
      status: status ?? this.status,
    );
  }
}

final salesHistoryProvider = StateNotifierProvider.autoDispose<SalesHistoryController, SalesHistoryState>((ref) {
  return SalesHistoryController(ref);
});

class SalesHistoryController extends StateNotifier<SalesHistoryState> {
  final Ref ref;
  SalesHistoryController(this.ref) : super(const SalesHistoryState()) {
    refreshForToday();
  }

  Future<void> refreshForToday() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    await load(from: start, to: start);
  }

  Future<void> load({DateTime? from, DateTime? to, String? status}) async {
    state = state.copyWith(loading: true, clearError: true, from: from, to: to, status: status);
    try {
      final repo = ref.read(salesRepositoryProvider);
      final response = await repo.listMySales(from: from, to: to, status: status);
      state = state.copyWith(items: response['items'] as List<SaleModel>, summary: response['summary'] as Map<String, dynamic>, loading: false);
    } catch (e) {
      final msg = e is ApiException ? e.message : 'No se pudo cargar el historial';
      state = state.copyWith(loading: false, error: msg);
    }
  }
}

class AdminSalesState {
  final List<SaleModel> items;
  final Map<String, dynamic> summary;
  final Map<String, dynamic> kpis;
  final bool loading;
  final String? error;

  const AdminSalesState({
    this.items = const [],
    this.summary = const {},
    this.kpis = const {},
    this.loading = false,
    this.error,
  });

  AdminSalesState copyWith({
    List<SaleModel>? items,
    Map<String, dynamic>? summary,
    Map<String, dynamic>? kpis,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return AdminSalesState(
      items: items ?? this.items,
      summary: summary ?? this.summary,
      kpis: kpis ?? this.kpis,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final adminSalesProvider = StateNotifierProvider.autoDispose<AdminSalesController, AdminSalesState>((ref) {
  return AdminSalesController(ref);
});

class AdminSalesController extends StateNotifier<AdminSalesState> {
  final Ref ref;
  AdminSalesController(this.ref) : super(const AdminSalesState()) {
    refresh();
  }

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final repo = ref.read(salesRepositoryProvider);
      final data = await repo.adminSales();
      final kpis = await repo.adminSummary();
      state = state.copyWith(items: data['items'] as List<SaleModel>, summary: data['summary'] as Map<String, dynamic>, kpis: kpis, loading: false);
    } catch (e) {
      final msg = e is ApiException ? e.message : 'No se pudo cargar ventas admin';
      state = state.copyWith(loading: false, error: msg);
    }
  }
}
