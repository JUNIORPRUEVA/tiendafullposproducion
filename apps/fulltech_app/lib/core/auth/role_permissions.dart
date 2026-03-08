import 'app_permissions.dart';
import 'app_role.dart';

/// Legacy helpers kept for backwards compatibility.
/// New code should prefer [AppRole]/[AppPermission] + [hasPermission].

String normalizeRole(String? role) {
  // Preserve historical behaviour (uppercase) while using the new normalizer.
  final key = normalizeRoleKey(role);
  return key.toUpperCase();
}

bool canAccessContabilidadByRole(String? role) {
  return hasPermission(parseAppRole(role), AppPermission.viewAccounting);
}

bool canSendLocationByRole(String? role) {
  return parseAppRole(role).isTechnician;
}
