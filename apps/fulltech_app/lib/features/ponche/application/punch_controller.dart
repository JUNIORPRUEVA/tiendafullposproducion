import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/models/punch_model.dart';
import '../data/punch_repository.dart';

class PunchState {
  final List<PunchModel> items;
  final bool loading;
  final bool creating;
  final String? error;

  const PunchState({
    this.items = const [],
    this.loading = false,
    this.creating = false,
    this.error,
  });

  PunchState copyWith({
    List<PunchModel>? items,
    bool? loading,
    bool? creating,
    String? error,
    bool clearError = false,
  }) {
    return PunchState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      creating: creating ?? this.creating,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final punchControllerProvider =
    StateNotifierProvider.autoDispose<PunchController, PunchState>((ref) {
      // Recreate/clear state when el usuario cambia para no mostrar ponches de otra sesión.
      ref.watch(authStateProvider);
      return PunchController(ref);
    });

class PunchController extends StateNotifier<PunchState> {
  final Ref ref;

  PunchController(this.ref) : super(const PunchState()) {
    load();
  }

  Future<void> load({DateTime? from, DateTime? to}) async {
    if (!mounted) return;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final repo = ref.read(punchRepositoryProvider);
      final items = await repo.listMine(from: from, to: to);
      if (!mounted) return;
      state = state.copyWith(items: items, loading: false);
    } catch (e) {
      final message = e is ApiException
          ? e.message
          : 'No se pudo cargar el historial';
      if (!mounted) return;
      state = state.copyWith(loading: false, error: message);
    }
  }

  Future<PunchModel> register(PunchType type) async {
    if (!mounted) {
      throw ApiException('Operación cancelada');
    }
    state = state.copyWith(creating: true, clearError: true);
    try {
      final repo = ref.read(punchRepositoryProvider);
      final punch = await repo.createPunch(type);
      if (mounted) {
        state = state.copyWith(creating: false, items: [punch, ...state.items]);
      }
      return punch;
    } catch (e) {
      final message = e is ApiException
          ? e.message
          : 'No se pudo registrar el ponche';
      if (mounted) {
        state = state.copyWith(creating: false, error: message);
      }
      throw ApiException(message);
    }
  }
}
