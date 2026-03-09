import 'app_role.dart';

/// Central permission list used by routing, navigation and UI actions.
/// Keep this small and meaningful (module/screen/action-level capabilities).
enum AppPermission {
  // Common
  viewProfile,
  viewMyPayments,

  // Scheduling
  viewWorkScheduling,
  manageWorkScheduling,

  // Core modules
  viewOperations,
  viewPunch,

  // Technician
  viewTechDepartures,

  // Sales/CRM
  viewCatalog,
  viewSales,
  viewQuotes,
  viewClients,

  // Accounting
  viewAccounting,
  viewCompanyManual,

  // Admin
  viewAdminPanel,
  manageUsers,
  manageSettings,
  managePayroll,
  manageCompanyManual,
  viewAdminTechDepartures,
}

/// Role → permissions map. This is the *only* place to change access rules.
///
/// IMPORTANT: Technician is intentionally restricted to a technician-focused
/// experience (operations + punch + self areas).
const Map<AppRole, Set<AppPermission>> rolePermissions = {
  AppRole.admin: {
    AppPermission.viewProfile,
    AppPermission.viewMyPayments,
    AppPermission.viewWorkScheduling,
    AppPermission.manageWorkScheduling,
    AppPermission.viewOperations,
    AppPermission.viewPunch,
    AppPermission.viewCatalog,
    AppPermission.viewSales,
    AppPermission.viewQuotes,
    AppPermission.viewClients,
    AppPermission.viewAccounting,
    AppPermission.viewCompanyManual,
    AppPermission.viewAdminPanel,
    AppPermission.manageUsers,
    AppPermission.manageSettings,
    AppPermission.managePayroll,
    AppPermission.manageCompanyManual,
    AppPermission.viewAdminTechDepartures,
  },
  AppRole.asistente: {
    AppPermission.viewProfile,
    AppPermission.viewMyPayments,
    AppPermission.viewWorkScheduling,
    AppPermission.viewOperations,
    AppPermission.viewPunch,
    AppPermission.viewCatalog,
    AppPermission.viewSales,
    AppPermission.viewQuotes,
    AppPermission.viewClients,
    AppPermission.viewAccounting,
    AppPermission.viewCompanyManual,
  },
  AppRole.vendedor: {
    AppPermission.viewProfile,
    AppPermission.viewMyPayments,
    AppPermission.viewWorkScheduling,
    AppPermission.viewOperations,
    AppPermission.viewPunch,
    AppPermission.viewCatalog,
    AppPermission.viewSales,
    AppPermission.viewQuotes,
    AppPermission.viewClients,
    AppPermission.viewCompanyManual,
  },
  AppRole.marketing: {
    AppPermission.viewProfile,
    AppPermission.viewMyPayments,
    AppPermission.viewWorkScheduling,
    AppPermission.viewOperations,
    AppPermission.viewPunch,
    AppPermission.viewCatalog,
    AppPermission.viewQuotes,
    AppPermission.viewClients,
    AppPermission.viewCompanyManual,
  },
  AppRole.tecnico: {
    AppPermission.viewProfile,
    AppPermission.viewMyPayments,
    AppPermission.viewWorkScheduling,
    AppPermission.viewOperations,
    AppPermission.viewPunch,
    AppPermission.viewTechDepartures,
    AppPermission.viewCompanyManual,
  },
  AppRole.unknown: {
    // Least privilege (still allow self areas to avoid redirect loops)
    AppPermission.viewProfile,
    // App should still land on Operaciones by default.
    AppPermission.viewOperations,
  },
};

bool hasPermission(AppRole role, AppPermission permission) {
  final set = rolePermissions[role];
  if (set == null) return false;
  return set.contains(permission);
}
