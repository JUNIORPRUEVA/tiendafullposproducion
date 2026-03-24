import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/models/user_model.dart';
import '../../../features/user/data/users_repository.dart';
import '../../clientes/cliente_model.dart';
import '../../clientes/data/clientes_repository.dart';
import '../data/service_orders_api.dart';
import '../data/service_orders_local_cache.dart';
import '../service_order_models.dart';

class ServiceOrdersListState {
  final bool loading;
  final bool refreshing;
  final String? error;
  final List<ServiceOrderModel> items;
  final Map<String, ClienteModel> clientsById;
  final Map<String, UserModel> usersById;

  const ServiceOrdersListState({
    this.loading = false,
    this.refreshing = false,
    this.error,
    this.items = const [],
    this.clientsById = const {},
    this.usersById = const {},
  });

  ServiceOrdersListState copyWith({
    bool? loading,
    bool? refreshing,
    String? error,
    List<ServiceOrderModel>? items,
    Map<String, ClienteModel>? clientsById,
    Map<String, UserModel>? usersById,
    bool clearError = false,
  }) {
    return ServiceOrdersListState(
      loading: loading ?? this.loading,
      refreshing: refreshing ?? this.refreshing,
      error: clearError ? null : (error ?? this.error),
      items: items ?? this.items,
      clientsById: clientsById ?? this.clientsById,
      usersById: usersById ?? this.usersById,
    );
  }
}

final serviceOrdersListControllerProvider =
    StateNotifierProvider<ServiceOrdersListController, ServiceOrdersListState>((
      ref,
    ) {
      return ServiceOrdersListController(ref);
    });

class ServiceOrdersListController
    extends StateNotifier<ServiceOrdersListState> {
  ServiceOrdersListController(this.ref)
    : super(const ServiceOrdersListState()) {
    load();
  }

  final Ref ref;
  Future<void>? _inFlightLoad;

  Map<String, ClienteModel> _clientMapFromOrders(List<ServiceOrderModel> orders) {
    return {
      for (final order in orders)
        if (order.client != null) order.client!.id: order.client!,
    };
  }

  Future<void> _persistItems(List<ServiceOrderModel> items) {
    return ref.read(serviceOrdersLocalCacheProvider).saveListSnapshot(items);
  }

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

    if (!refresh && state.items.isEmpty) {
      final cachedOrders = await ref.read(serviceOrdersLocalCacheProvider).getCachedList();
      if (cachedOrders.isNotEmpty) {
        cachedOrders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        state = state.copyWith(
          loading: false,
          refreshing: true,
          items: cachedOrders,
          clientsById: _clientMapFromOrders(cachedOrders),
          clearError: true,
        );
      }
    }

    state = state.copyWith(
      loading: !refresh && state.items.isEmpty,
      refreshing: refresh || state.items.isNotEmpty,
      clearError: true,
    );
    _inFlightLoad = () async {
      try {
        final orders = await ref.read(serviceOrdersApiProvider).listOrders();
        final clients = await ref
            .read(clientesRepositoryProvider)
            .listClients(ownerId: _ownerId, pageSize: 200)
            .catchError((_) => <ClienteModel>[]);
        final users = await ref
            .read(usersRepositoryProvider)
            .getAllUsers()
            .catchError((_) => <UserModel>[]);
        final clientMap = <String, ClienteModel>{
          for (final client in clients) client.id: client,
        };
        final userMap = <String, UserModel>{for (final user in users) user.id: user};

        for (final order in orders) {
          final embeddedClient = order.client;
          if (embeddedClient != null) {
            clientMap[embeddedClient.id] = embeddedClient;
          }
        }

        orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        await _persistItems(orders);
        state = state.copyWith(
          loading: false,
          refreshing: false,
          items: orders,
          clientsById: clientMap,
          usersById: userMap,
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
    await _persistItems(items);
    await ref.read(serviceOrdersLocalCacheProvider).removeOrder(id);
  }

  void upsertOrder(ServiceOrderModel order) {
    final nextClientMap = {...state.clientsById};
    if (order.client != null) {
      nextClientMap[order.client!.id] = order.client!;
    }
    final items = [...state.items];
    final index = items.indexWhere((item) => item.id == order.id);
    if (index >= 0) {
      items[index] = order;
    } else {
      items.add(order);
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    state = state.copyWith(
      items: items,
      clientsById: nextClientMap,
    );
    unawaited(_persistItems(items));
    unawaited(ref.read(serviceOrdersLocalCacheProvider).saveOrder(order));
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
    unawaited(_persistItems(items));
  }
}
