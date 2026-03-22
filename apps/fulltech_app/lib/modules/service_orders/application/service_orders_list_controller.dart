import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/errors/api_exception.dart';
import '../../clientes/cliente_model.dart';
import '../../clientes/data/clientes_repository.dart';
import '../data/service_orders_api.dart';
import '../service_order_models.dart';

class ServiceOrdersListState {
  final bool loading;
  final bool refreshing;
  final String? error;
  final List<ServiceOrderModel> items;
  final Map<String, ClienteModel> clientsById;

  const ServiceOrdersListState({
    this.loading = false,
    this.refreshing = false,
    this.error,
    this.items = const [],
    this.clientsById = const {},
  });

  ServiceOrdersListState copyWith({
    bool? loading,
    bool? refreshing,
    String? error,
    List<ServiceOrderModel>? items,
    Map<String, ClienteModel>? clientsById,
    bool clearError = false,
  }) {
    return ServiceOrdersListState(
      loading: loading ?? this.loading,
      refreshing: refreshing ?? this.refreshing,
      error: clearError ? null : (error ?? this.error),
      items: items ?? this.items,
      clientsById: clientsById ?? this.clientsById,
    );
  }
}

final serviceOrdersListControllerProvider = StateNotifierProvider<
    ServiceOrdersListController, ServiceOrdersListState>((ref) {
  return ServiceOrdersListController(ref);
});

class ServiceOrdersListController extends StateNotifier<ServiceOrdersListState> {
  ServiceOrdersListController(this.ref) : super(const ServiceOrdersListState()) {
    load();
  }

  final Ref ref;

  String get _ownerId => ref.read(authStateProvider).user?.id ?? '';

  Future<void> load({bool refresh = false}) async {
    state = state.copyWith(
      loading: !refresh && state.items.isEmpty,
      refreshing: refresh || state.items.isNotEmpty,
      clearError: true,
    );
    try {
      final results = await Future.wait<dynamic>([
        ref.read(serviceOrdersApiProvider).listOrders(),
        ref.read(clientesRepositoryProvider).listClients(
              ownerId: _ownerId,
              pageSize: 200,
            ),
      ]);
      final orders = results[0] as List<ServiceOrderModel>;
      final clients = results[1] as List<ClienteModel>;
      final clientMap = <String, ClienteModel>{
        for (final client in clients) client.id: client,
      };

      orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      state = state.copyWith(
        loading: false,
        refreshing: false,
        items: orders,
        clientsById: clientMap,
      );
    } catch (error) {
      final message = error is ApiException
          ? error.message
          : 'No se pudieron cargar las órdenes';
      state = state.copyWith(
        loading: false,
        refreshing: false,
        error: message,
      );
    }
  }

  Future<void> refresh() => load(refresh: true);
}