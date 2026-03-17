import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../data/operations_repository.dart';
import 'operations_controller.dart';
import '../tecnico/application/tech_operations_controller.dart';

class OperationsPrefetchController {
  Timer? _timer;
  String _lastUserId = '';

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  void onAuthChanged(Ref ref, AuthState auth) {
    if (!auth.isAuthenticated) {
      _timer?.cancel();
      _timer = null;
      _lastUserId = '';
      return;
    }

    final userId = (auth.user?.id ?? '').trim();
    if (userId.isEmpty) return;
    if (userId == _lastUserId) return;

    _lastUserId = userId;

    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 900), () {
      // Warm up caches in background. Do NOT block first paint.
      try {
        ref.read(operationsControllerProvider.notifier);
        final repo = ref.read(operationsRepositoryProvider);
        unawaited(repo.getTechnicians(forceRefresh: true, silent: true));
        unawaited(repo.listChecklistCategoriesAndCache(silent: true));
        unawaited(repo.listChecklistPhasesAndCache(silent: true));

        final role = (auth.user?.role ?? '').trim().toLowerCase();
        if (role == 'tecnico') {
          ref.read(techOperationsControllerProvider.notifier);
        }
      } catch (_) {
        // Best-effort
      }
    });
  }
}

final operationsPrefetchControllerProvider =
    Provider<OperationsPrefetchController>((ref) {
      final controller = OperationsPrefetchController();
      ref.onDispose(controller.dispose);
      return controller;
    });

/// Bootstrap que se mantiene vivo mientras haya sesión.
/// Se debe `watch`ear desde un widget que viva toda la app (por ejemplo `MyApp`).
final operationsPrefetchBootstrapProvider = Provider<void>((ref) {
  final auth = ref.watch(authStateProvider);
  final controller = ref.watch(operationsPrefetchControllerProvider);
  controller.onAuthChanged(ref, auth);
});
