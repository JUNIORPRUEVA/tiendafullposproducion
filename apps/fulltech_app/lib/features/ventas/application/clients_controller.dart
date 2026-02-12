import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/models/client_model.dart';
import '../data/sales_repository.dart';

class ClientsState {
  final List<ClientModel> items;
  final bool loading;
  final bool saving;
  final String? error;
  final String? actionError;

  const ClientsState({
    this.items = const [],
    this.loading = false,
    this.saving = false,
    this.error,
    this.actionError,
  });

  ClientsState copyWith({
    List<ClientModel>? items,
    bool? loading,
    bool? saving,
    String? error,
    String? actionError,
    bool clearError = false,
  }) {
    return ClientsState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      error: clearError ? null : (error ?? this.error),
      actionError: clearError ? null : (actionError ?? this.actionError),
    );
  }
}

final clientsControllerProvider = StateNotifierProvider.autoDispose<ClientsController, ClientsState>((ref) {
  return ClientsController(ref);
});

class ClientsController extends StateNotifier<ClientsState> {
  final Ref ref;
  ClientsController(this.ref) : super(const ClientsState()) {
    load();
  }

  Future<void> load({String? search}) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final repo = ref.read(salesRepositoryProvider);
      final clients = await repo.fetchClients(search: search);
      state = state.copyWith(items: clients, loading: false);
    } catch (e) {
      final msg = e is ApiException ? e.message : 'No se pudieron cargar los clientes';
      state = state.copyWith(loading: false, error: msg);
    }
  }

  Future<ClientModel> create({required String nombre, required String telefono, String? email, String? direccion, String? notas}) async {
    state = state.copyWith(saving: true, clearError: true);
    try {
      final repo = ref.read(salesRepositoryProvider);
      final created = await repo.createClient(nombre: nombre, telefono: telefono, email: email, direccion: direccion, notas: notas);
      state = state.copyWith(items: [created, ...state.items], saving: false);
      return created;
    } catch (e) {
      final msg = e is ApiException ? e.message : 'No se pudo crear el cliente';
      state = state.copyWith(saving: false, actionError: msg);
      throw Exception(msg);
    }
  }

  Future<void> update(String id, {required String nombre, String? telefono, String? email, String? direccion, String? notas}) async {
    state = state.copyWith(saving: true, clearError: true);
    try {
      final repo = ref.read(salesRepositoryProvider);
      final updated = await repo.updateClient(id, nombre: nombre, telefono: telefono, email: email, direccion: direccion, notas: notas);
      final items = state.items.map((c) => c.id == id ? updated : c).toList();
      state = state.copyWith(items: items, saving: false);
    } catch (e) {
      final msg = e is ApiException ? e.message : 'No se pudo actualizar el cliente';
      state = state.copyWith(saving: false, actionError: msg);
      rethrow;
    }
  }

  Future<void> remove(String id) async {
    state = state.copyWith(saving: true, clearError: true);
    try {
      await ref.read(salesRepositoryProvider).deleteClient(id);
      state = state.copyWith(items: state.items.where((c) => c.id != id).toList(), saving: false);
    } catch (e) {
      final msg = e is ApiException ? e.message : 'No se pudo eliminar el cliente';
      state = state.copyWith(saving: false, actionError: msg);
      rethrow;
    }
  }
}
