import '../auth/app_permissions.dart';
import '../auth/app_role.dart';
import 'routes.dart';

/// Maps routes to the permission required to access them.
///
/// This is enforced at the router level (deep-link safe) and reused
/// by navigation (drawer/tabs) to avoid duplicating logic.
class RouteAccess {
  static AppPermission? permissionForLocation(String location) {
    final path = location.split('?').first;

    // Exact matches first
    switch (path) {
      case Routes.profile:
        return AppPermission.viewProfile;
      case Routes.misPagos:
        return AppPermission.viewMyPayments;
      case Routes.horarios:
        return AppPermission.viewWorkScheduling;
      case Routes.operaciones:
      case Routes.operacionesAgenda:
      case Routes.operacionesMapaClientes:
      case Routes.operacionesReglas:
      case Routes.operacionesChecklistConfig:
        return AppPermission.viewOperations;
      case Routes.operacionesTecnico:
      case Routes.operacionesTecnicoDetalle:
        return AppPermission.viewTechOperations;
      case Routes.salidasTecnicas:
        return AppPermission.viewTechDepartures;
      case Routes.ponche:
        return AppPermission.viewPunch;
      case Routes.catalogo:
        return AppPermission.viewCatalog;
      case Routes.ventas:
      case Routes.registrarVenta:
        return AppPermission.viewSales;
      case Routes.cotizaciones:
      case Routes.cotizacionesHistorial:
        return AppPermission.viewQuotes;
      case Routes.clientes:
      case Routes.clienteNuevo:
        return AppPermission.viewClients;
      case Routes.nomina:
        return AppPermission.managePayroll;
      case Routes.manualInterno:
        return AppPermission.viewCompanyManual;
      case Routes.contabilidad:
      case Routes.contabilidadCierresDiarios:
      case Routes.contabilidadFacturaFiscal:
      case Routes.contabilidadPagosPendientes:
        return AppPermission.viewAccounting;
      case Routes.administracion:
        return AppPermission.viewAdminPanel;
      case Routes.configuracion:
        return AppPermission.manageSettings;
      case Routes.users:
      case Routes.user:
        return AppPermission.manageUsers;
    }

    // Prefix matches (parameterized routes)
    if (path.startsWith('/clientes/')) {
      return AppPermission.viewClients;
    }
    if (path.startsWith('/users/')) {
      return AppPermission.manageUsers;
    }
    if (path.startsWith('${Routes.contabilidad}/')) {
      return AppPermission.viewAccounting;
    }
    if (path.startsWith('${Routes.administracion}/')) {
      return AppPermission.viewAdminPanel;
    }
    if (path.startsWith('${Routes.operacionesTecnico}/') ||
        path.startsWith(Routes.operacionesTecnico)) {
      return AppPermission.viewTechOperations;
    }
    if (path.startsWith('${Routes.operaciones}/')) {
      return AppPermission.viewOperations;
    }
    if (path.startsWith('${Routes.salidasTecnicas}/')) {
      return AppPermission.viewTechDepartures;
    }

    return null;
  }

  static String defaultHomeForRole(AppRole role) {
    // UX requirement: app always opens on Operaciones.
    if (hasPermission(role, AppPermission.viewOperations)) {
      return Routes.operaciones;
    }

    // Safe fallback if permissions are misconfigured.
    return Routes.profile;
  }
}
