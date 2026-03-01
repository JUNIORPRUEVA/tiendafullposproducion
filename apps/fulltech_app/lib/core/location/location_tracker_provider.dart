import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';
import '../auth/auth_repository.dart';
import '../auth/role_permissions.dart';
import 'location_tracker.dart';

final locationTrackerProvider = Provider<LocationTracker>((ref) {
  final dio = ref.watch(dioProvider);
  final tracker = LocationTracker(dio: dio);
  ref.onDispose(tracker.dispose);
  return tracker;
});

/// Provider “bootstrap” para arrancar/parar el tracker en base al estado auth.
///
/// Se debe `watch`ear desde un widget que viva mientras el usuario esté logueado
/// (por ejemplo, el `HomeShell`).
final locationTrackingBootstrapProvider = Provider<void>((ref) {
  final auth = ref.watch(authStateProvider);
  final tracker = ref.watch(locationTrackerProvider);

  final canSendLocation =
      auth.isAuthenticated && canSendLocationByRole(auth.user?.role);

  if (canSendLocation) {
    unawaited(tracker.start());
  } else {
    tracker.stop();
  }
});
