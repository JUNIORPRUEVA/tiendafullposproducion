import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_provider.dart';
import '../../data/operations_repository.dart';
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
  int _loadSeq = 0;

  TechOperationsController(this.ref) : super(const TechOperationsState()) {
    load();
  }

  Future<void> load({bool silent = false}) async {
    final seq = ++_loadSeq;

    final repo = ref.read(operationsRepositoryProvider);
    final user = ref.read(authStateProvider).user;
    final role = (user?.role ?? '').trim().toLowerCase();
    final userId = (user?.id ?? '').trim();

    final techFilterId = (role == 'tecnico' && userId.isNotEmpty)
        ? userId
        : null;

    final cacheScope = userId;
    final techKey = techFilterId ?? 'all';

    try {
      final cached = await repo.getCachedTechServices(
        cacheScope: cacheScope,
        techKey: techKey,
      );

      final hasCached = cached != null && cached.isNotEmpty;
      if (!silent) {
        state = state.copyWith(
          loading: !hasCached && state.services.isEmpty,
          clearError: true,
          services: cached ?? state.services,
        );
      } else if (hasCached && state.services.isEmpty) {
        state = state.copyWith(
          loading: false,
          clearError: true,
          services: cached,
        );
      }

      unawaited(() async {
        try {
          final fresh = await repo.listTechServicesAndCache(
            cacheScope: cacheScope,
            techKey: techKey,
            technicianId: techFilterId,
            assignedTo: techFilterId,
            silent: true,
          );
          if (!mounted || seq != _loadSeq) return;
          state = state.copyWith(loading: false, services: fresh);
        } catch (e) {
          if (!mounted || seq != _loadSeq) return;
          state = state.copyWith(loading: false, error: e.toString());
        }
      }());
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> refresh({bool silent = false}) => load(silent: silent);

  void applyRealtimeService(ServiceModel service) {
    final before = state.services;
    if (before.isEmpty) return;
    final index = before.indexWhere((s) => s.id == service.id);
    if (index < 0) return;
    final next = [...before];
    next[index] = service;
    state = state.copyWith(services: next);
  }
}
