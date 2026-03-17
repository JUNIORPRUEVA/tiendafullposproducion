import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/errors/api_exception.dart';
import '../cliente_model.dart';
import '../data/clientes_repository.dart';

class ClientesState {
  final List<ClienteModel> items;
  final bool loading;
  final bool refreshing;
  final bool saving;
  final String? error;
  final String? actionError;
  final String search;
  final ClientesOrder order;
  final CorreoFilter correoFilter;
  final EstadoFilter estadoFilter;

  const ClientesState({
    this.items = const [],
    this.loading = false,
    this.refreshing = false,
    this.saving = false,
    this.error,
    this.actionError,
    this.search = '',
    this.order = ClientesOrder.az,
    this.correoFilter = CorreoFilter.todos,
    this.estadoFilter = EstadoFilter.activos,
  });

  ClientesState copyWith({
    List<ClienteModel>? items,
    bool? loading,
    bool? refreshing,
    bool? saving,
    String? error,
    String? actionError,
    String? search,
    ClientesOrder? order,
    CorreoFilter? correoFilter,
    EstadoFilter? estadoFilter,
    bool clearError = false,
    bool clearActionError = false,
  }) {
    return ClientesState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      refreshing: refreshing ?? this.refreshing,
      saving: saving ?? this.saving,
      error: clearError ? null : (error ?? this.error),
      actionError: clearActionError ? null : (actionError ?? this.actionError),
      search: search ?? this.search,
      order: order ?? this.order,
      correoFilter: correoFilter ?? this.correoFilter,
      estadoFilter: estadoFilter ?? this.estadoFilter,
    );
  }
}

final clientesControllerProvider =
    StateNotifierProvider<ClientesController, ClientesState>((ref) {
  return ClientesController(ref);
});

class ClientesController extends StateNotifier<ClientesState> {
  final Ref ref;
  int _loadSeq = 0;

  ClientesController(this.ref) : super(const ClientesState()) {
    load();
  }

  String get _ownerId => ref.read(authStateProvider).user?.id ?? 'default_owner';

  Future<void> load({String? search}) async {
    final seq = ++_loadSeq;
    final nextSearch = search ?? state.search;
    final repo = ref.read(clientesRepositoryProvider);

    final cached = await repo.getCachedClients(
      ownerId: _ownerId,
      search: nextSearch,
      order: state.order,
      correoFilter: state.correoFilter,
      estadoFilter: state.estadoFilter,
    );

    final hasCached = cached.isNotEmpty;
    state = state.copyWith(
      search: nextSearch,
      loading: !hasCached && state.items.isEmpty,
      refreshing: hasCached || state.items.isNotEmpty,
      items: hasCached ? cached : state.items,
      clearError: true,
      clearActionError: true,
    );

    try {
      final items = await repo.listClientsAndCache(
        ownerId: _ownerId,
        search: nextSearch,
        order: state.order,
        correoFilter: state.correoFilter,
        estadoFilter: state.estadoFilter,
      );
      if (seq != _loadSeq) return;
      state = state.copyWith(
        items: items,
        loading: false,
        refreshing: false,
      );
    } catch (e) {
      if (seq != _loadSeq) return;
      final message = e is ApiException
          ? e.message
          : 'No se pudieron cargar los clientes';
      state = state.copyWith(
        loading: false,
        refreshing: false,
        error: message,
      );
    }
  }

  Future<void> refresh() => load();

  Future<void> applyFilters({
    ClientesOrder? order,
    CorreoFilter? correoFilter,
    EstadoFilter? estadoFilter,
  }) async {
    state = state.copyWith(
      order: order ?? state.order,
      correoFilter: correoFilter ?? state.correoFilter,
      estadoFilter: estadoFilter ?? state.estadoFilter,
    );
    await load();
  }

  bool _hasPhoneDuplicate(String telefono, {String? excludingId}) {
    final normalized = telefono.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    if (normalized.isEmpty) return false;
    return state.items.any((cliente) {
      final samePhone =
          cliente.telefono.trim().replaceAll(RegExp(r'[^0-9+]'), '') ==
          normalized;
      final differentId = excludingId == null || cliente.id != excludingId;
      return samePhone && differentId && !cliente.isDeleted;
    });
  }

  Future<void> _persistSnapshot(List<ClienteModel> items) {
    return ref.read(clientesRepositoryProvider).saveClientsSnapshot(
      ownerId: _ownerId,
      search: state.search,
      order: state.order,
      correoFilter: state.correoFilter,
      estadoFilter: state.estadoFilter,
      items: items,
    );
  }

  Future<ClienteModel> getById(String id) async {
    final local = state.items.where((c) => c.id == id).cast<ClienteModel?>().firstWhere(
          (element) => element != null,
          orElse: () => null,
        );
    if (local != null) return local;

    final repo = ref.read(clientesRepositoryProvider);
    return repo.getClientById(ownerId: _ownerId, id: id);
  }

  Future<void> saveCliente({
    required String nombre,
    required String telefono,
    String? direccion,
    String? correo,
    String? id,
  }) async {
    state = state.copyWith(saving: true, clearActionError: true);
    final repo = ref.read(clientesRepositoryProvider);

    try {
      final duplicated = _hasPhoneDuplicate(
        telefono,
        excludingId: (id ?? '').isEmpty ? null : id,
      );
      if (duplicated) {
        throw ApiException('Ya existe un cliente activo con ese teléfono.');
      }

      final now = DateTime.now();
      final optimistic = ClienteModel(
        id: (id ?? '').isEmpty
            ? 'local_${DateTime.now().microsecondsSinceEpoch}'
            : id!,
        ownerId: _ownerId,
        nombre: nombre.trim(),
        telefono: telefono.trim(),
        direccion: (direccion ?? '').trim().isEmpty ? null : direccion?.trim(),
        correo: (correo ?? '').trim().isEmpty ? null : correo?.trim(),
        createdAt: id == null ? now : null,
        updatedAt: now,
        updatedLocal: true,
        syncStatus: 'pending',
      );

      final previous = state.items;
      final optimisticItems = [
        if ((id ?? '').isEmpty) optimistic,
        for (final item in previous)
          if (item.id == optimistic.id || ((id ?? '').isNotEmpty && item.id == id))
            optimistic
          else
            item,
      ];
      final nextItems = (id ?? '').isEmpty ? optimisticItems : optimisticItems;

      state = state.copyWith(items: nextItems, saving: true);
      await _persistSnapshot(nextItems);

      final synced = await repo.syncUpsertClientOrQueue(
        ownerId: _ownerId,
        cliente: optimistic,
      );
      final merged = [
        for (final item in state.items)
          if (item.id == optimistic.id) synced else item,
      ];
      state = state.copyWith(items: merged, saving: false);
      await _persistSnapshot(merged);
    } catch (e) {
      final message = e is ApiException ? e.message : 'No se pudo guardar el cliente';
      state = state.copyWith(saving: false, actionError: message);
      await load(search: state.search);
      rethrow;
    }
  }

  Future<void> remove(String id) async {
    state = state.copyWith(saving: true, clearActionError: true);
    final previous = state.items;
    state = state.copyWith(
      items: previous.where((c) => c.id != id).toList(),
    );

    try {
      final repo = ref.read(clientesRepositoryProvider);
      await _persistSnapshot(state.items);
      await repo.syncDeleteClientOrQueue(ownerId: _ownerId, id: id);
      state = state.copyWith(saving: false);
    } catch (e) {
      final message = e is ApiException ? e.message : 'No se pudo eliminar el cliente';
      state = state.copyWith(
        items: previous,
        saving: false,
        actionError: message,
      );
      await _persistSnapshot(previous);
      rethrow;
    }
  }
}
