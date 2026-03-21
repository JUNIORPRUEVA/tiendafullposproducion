import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/realtime/operations_realtime_service.dart';
import '../data/operations_repository.dart';
import '../operations_models.dart';
import 'operations_controller.dart';

final operationsRealtimeBootstrapProvider = Provider<void>((ref) {
  final realtime = ref.read(operationsRealtimeServiceProvider);

  Timer? refreshDebounce;

  bool hasFullServiceSnapshot(Map<String, dynamic>? service) {
    if (service == null) return false;
    final id = (service['id'] ?? '').toString().trim();
    if (id.isEmpty) return false;
    final title = (service['title'] ?? '').toString().trim();
    final status = (service['status'] ?? '').toString().trim();
    final phase =
        (service['phase'] ?? service['currentPhase'] ?? '')
            .toString()
            .trim();
    final customer = service['customer'];
    final hasCustomer = customer is Map && customer.isNotEmpty;
    return title.isNotEmpty || status.isNotEmpty || phase.isNotEmpty || hasCustomer;
  }

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
    });
  }

  final sub = realtime.stream.listen((msg) {
    final auth = ref.read(authStateProvider);
    final cacheScope = (auth.user?.id ?? '').trim();
    final currentUserRole = (auth.user?.role ?? '').trim().toLowerCase();
    final serviceId =
        ((msg.serviceId ?? msg.service?['id']) ?? '').toString().trim();
    final fullSnapshot = hasFullServiceSnapshot(msg.service);

    if (cacheScope.isNotEmpty && serviceId.isNotEmpty) {
      final technicianId = currentUserRole == 'tecnico' ? cacheScope : null;
      unawaited(
        ref.read(operationsRepositoryProvider).warmServiceDetailCaches(
          cacheScope: cacheScope,
          serviceId: serviceId,
          technicianId: technicianId,
        ),
      );
    }

    if (fullSnapshot && msg.service != null) {
      // Best-effort: update detail cache for instant "open detail".
      if (cacheScope.isNotEmpty) {
        unawaited(
          ref
              .read(operationsRepositoryProvider)
              .upsertServiceCacheFromRealtime(
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
        ref.invalidate(serviceProvider(service.id));
      } catch (_) {
        // Ignore parse errors; we'll reconcile via refresh below.
      }
    } else if (serviceId.isNotEmpty) {
      ref.invalidate(serviceProvider(serviceId));
    }

    // Reconcile filters/order/dashboard with a debounced refresh.
    scheduleRefresh();
  });

  ref.onDispose(() {
    refreshDebounce?.cancel();
    sub.cancel();
  });
});
