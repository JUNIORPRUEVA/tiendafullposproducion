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
  Future<void>? _inFlightLoad;

  String _friendlyListMessage(Object error) {
    if (error is ApiException) {
      if (error.type == ApiErrorType.forbidden || error.code == 403) {
        return 'No tienes permiso para ver las órdenes de servicio';
      }
      return error.message;
    }
    return 'No se pudieron cargar las órdenes. Error inesperado.';
  }

  String get _ownerId => ref.read(authStateProvider).user?.id ?? '';

  Future<void> load({bool refresh = false}) async {
    if (_inFlightLoad != null) {
      return _inFlightLoad!;
    }

    state = state.copyWith(
      loading: !refresh && state.items.isEmpty,
      refreshing: refresh || state.items.isNotEmpty,
      clearError: true,
    );
    _inFlightLoad = () async {
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
        final message = _friendlyListMessage(error);
        state = state.copyWith(
          loading: false,
          refreshing: false,
          error: message,
        );
      } finally {
        _inFlightLoad = null;
      }
    }();

    return _inFlightLoad!;
  }

  Future<void> refresh() => load(refresh: true);

  Future<void> retry() => load(refresh: true);

  Future<void> deleteOrder(String id) async {
    await ref.read(serviceOrdersApiProvider).deleteOrder(id);
    final items = state.items
        .where((item) => item.id != id)
        .toList(growable: false);
    state = state.copyWith(items: items);
  }

  void upsertOrder(ServiceOrderModel order) {
    final items = [...state.items];
    final index = items.indexWhere((item) => item.id == order.id);
    if (index >= 0) {
      items[index] = order;
    } else {
      items.add(order);
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    state = state.copyWith(items: items);
  }

  void replaceOrderStatus({
    required String orderId,
    required ServiceOrderStatus status,
  }) {
    final items = state.items
        .map(
          (item) => item.id == orderId ? item.copyWith(status: status) : item,
        )
        .toList(growable: false);
    state = state.copyWith(items: items);
  }
}