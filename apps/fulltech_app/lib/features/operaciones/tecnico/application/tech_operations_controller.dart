import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_provider.dart';
import '../../application/operations_controller.dart';
import '../../operations_models.dart';

class TechOperationsState {
  final bool loading;
  final String? error;
  final List<ServiceModel> services;

  const TechOperationsState({
    this.loading = false,
    this.error,
    this.services = const [],
  });

  TechOperationsState copyWith({
    bool? loading,
    String? error,
    List<ServiceModel>? services,
    bool clearError = false,
  }) {
    return TechOperationsState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      services: services ?? this.services,
    );
  }
}

final techOperationsControllerProvider =
    StateNotifierProvider<TechOperationsController, TechOperationsState>((ref) {
      return TechOperationsController(ref);
    });

class TechOperationsController extends StateNotifier<TechOperationsState> {
  final Ref ref;

  TechOperationsController(this.ref) : super(const TechOperationsState()) {
    ref.listen<OperationsState>(
      operationsControllerProvider,
      (_, next) => _syncFromSharedState(next),
      fireImmediately: true,
    );
    ref.listen<AuthState>(
      authStateProvider,
      (_, __) => _syncFromSharedState(ref.read(operationsControllerProvider)),
    );
  }

  Future<void> load({bool silent = false}) async {
    if (silent) {
      await ref.read(operationsControllerProvider.notifier).refresh();
      return;
    }
    state = state.copyWith(loading: true, clearError: true);
    await ref.read(operationsControllerProvider.notifier).refresh();
  }

  Future<void> refresh({bool silent = false}) => load(silent: silent);

  void applyRealtimeService(ServiceModel service) {
    final shared = ref.read(operationsControllerProvider);
    _syncFromSharedState(
      shared.copyWith(services: _mergeSnapshot(shared.services, service)),
    );
  }

  void _syncFromSharedState(OperationsState shared) {
    final filtered = shared.services
        .where(_belongsToCurrentList)
        .toList(growable: false);
    state = state.copyWith(
      loading: shared.loading || shared.refreshing,
      error: shared.error,
      services: filtered,
      clearError: shared.error == null,
    );
  }

  List<ServiceModel> _mergeSnapshot(
    List<ServiceModel> services,
    ServiceModel next,
  ) {
    final index = services.indexWhere((item) => item.id == next.id);
    final merged = [...services];
    if (index >= 0) {
      merged[index] = next;
    } else {
      merged.insert(0, next);
    }
    return merged;
  }

  bool _belongsToCurrentList(ServiceModel service) {
    final user = ref.read(authStateProvider).user;
    final role = (user?.role ?? '').trim().toLowerCase();
    final userId = (user?.id ?? '').trim();

    if (role != 'tecnico' || userId.isEmpty) return true;

    if ((service.technicianId ?? '').trim() == userId) return true;
    return service.assignments.any(
      (assignment) => assignment.userId.trim() == userId,
    );
  }
}
