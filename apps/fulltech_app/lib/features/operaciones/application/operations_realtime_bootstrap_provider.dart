import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/realtime/operations_realtime_service.dart';
import '../data/operations_repository.dart';
import '../operations_models.dart';
import 'operations_controller.dart';
import '../tecnico/application/tech_operations_controller.dart';

final operationsRealtimeBootstrapProvider = Provider<void>((ref) {
  final realtime = ref.read(operationsRealtimeServiceProvider);

  Timer? refreshDebounce;

  Future<void> connectFor(AuthState state) async {
    if (state.isAuthenticated) {
      unawaited(realtime.connect(state));
    } else {
      refreshDebounce?.cancel();
      refreshDebounce = null;
      realtime.disconnect();
    }
  }

  ref.listen<AuthState>(authStateProvider, (previous, next) {
    unawaited(connectFor(next));
  });

  // Initial sync.
  unawaited(connectFor(ref.read(authStateProvider)));

  void scheduleRefresh() {
    refreshDebounce?.cancel();
    refreshDebounce = Timer(const Duration(milliseconds: 650), () {
      unawaited(ref.read(operationsControllerProvider.notifier).refresh());
      unawaited(
        ref.read(techOperationsControllerProvider.notifier).refresh(silent: true),
      );
    });
  }

  final sub = realtime.stream.listen((msg) {
    final auth = ref.read(authStateProvider);
    final cacheScope = (auth.user?.id ?? '').trim();

    if (msg.service != null) {
      // Best-effort: update detail cache for instant "open detail".
      if (cacheScope.isNotEmpty) {
        unawaited(
          ref.read(operationsRepositoryProvider).upsertServiceCacheFromRealtime(
                cacheScope: cacheScope,
                serviceJson: msg.service!,
              ),
        );
      }

      try {
        final service = ServiceModel.fromJson(msg.service!);

        // Instant UI update when the item is already present.
        ref
            .read(operationsControllerProvider.notifier)
            .applyRealtimeService(service);
        ref
            .read(techOperationsControllerProvider.notifier)
            .applyRealtimeService(service);
      } catch (_) {
        // Ignore parse errors; we'll reconcile via refresh below.
      }
    }

    // Reconcile filters/order/dashboard with a debounced refresh.
    scheduleRefresh();
  });

  ref.onDispose(() {
    refreshDebounce?.cancel();
    sub.cancel();
  });
});
