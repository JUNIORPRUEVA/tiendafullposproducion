import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/errors/api_exception.dart';
import '../cliente_model.dart';
import '../data/clientes_repository.dart';

class ClientesState {
  final List<ClienteModel> items;
  final bool loading;
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

  ClientesController(this.ref) : super(const ClientesState()) {
    load();
  }

  String get _ownerId => ref.read(authStateProvider).user?.id ?? 'default_owner';

  Future<void> load({String? search}) async {
    final nextSearch = search ?? state.search;
    state = state.copyWith(
      loading: true,
      search: nextSearch,
      clearError: true,
      clearActionError: true,
    );

    try {
      final repo = ref.read(clientesRepositoryProvider);
      final items = await repo.listClients(
        ownerId: _ownerId,
        search: nextSearch,
        order: state.order,
        correoFilter: state.correoFilter,
        estadoFilter: state.estadoFilter,
      );
      state = state.copyWith(items: items, loading: false);
    } catch (e) {
      final message = e is ApiException ? e.message : 'No se pudieron cargar los clientes';
      state = state.copyWith(loading: false, error: message);
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
      final duplicated = await repo.existsPhoneDuplicate(
        ownerId: _ownerId,
        telefono: telefono,
        excludingId: (id ?? '').isEmpty ? null : id,
      );
      if (duplicated) {
        throw ApiException('Ya existe un cliente activo con ese teléfono.');
      }

      final now = DateTime.now();
      final cliente = ClienteModel(
        id: id ?? '',
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

      await repo.upsertClient(ownerId: _ownerId, cliente: cliente);
      await load();
      state = state.copyWith(saving: false);
    } catch (e) {
      final message = e is ApiException ? e.message : 'No se pudo guardar el cliente';
      state = state.copyWith(saving: false, actionError: message);
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
      await repo.softDeleteClient(ownerId: _ownerId, id: id);
      await load();
      state = state.copyWith(saving: false);
    } catch (e) {
      final message = e is ApiException ? e.message : 'No se pudo eliminar el cliente';
      state = state.copyWith(
        items: previous,
        saving: false,
        actionError: message,
      );
      rethrow;
    }
  }
}
