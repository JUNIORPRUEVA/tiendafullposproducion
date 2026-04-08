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
      case Routes.ponche:
      case Routes.poncheHistorial:
        return AppPermission.viewPunch;
      case Routes.catalogo:
        return AppPermission.viewCatalog;
      case Routes.ventas:
      case Routes.registrarVenta:
        return AppPermission.viewSales;
      case Routes.serviceOrders:
      case Routes.serviceOrderCreate:
        return AppPermission.viewOperations;
      case Routes.mediaGallery:
        return AppPermission.viewMediaGallery;
      case Routes.documentFlows:
        return AppPermission.viewDocumentFlows;
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
      case Routes.contabilidadDepositos:
      case Routes.contabilidadFacturaFiscal:
      case Routes.contabilidadPagosPendientes:
        return AppPermission.viewAccounting;
      case Routes.administracion:
      case Routes.administracionPonches:
      case Routes.administracionVentas:
      case Routes.administracionCotizaciones:
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
    if (path.startsWith('${Routes.ponche}/')) {
      return AppPermission.viewPunch;
    }
    if (path.startsWith('${Routes.serviceOrders}/')) {
      return AppPermission.viewOperations;
    }
    if (path.startsWith('${Routes.documentFlows}/')) {
      return AppPermission.viewDocumentFlows;
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
    return null;
  }

  static String defaultHomeForRole(AppRole role) {
    if (hasPermission(role, AppPermission.viewOperations)) {
      return Routes.serviceOrders;
    }
    if (hasPermission(role, AppPermission.viewClients)) {
      return Routes.clientes;
    }
    if (hasPermission(role, AppPermission.viewSales)) {
      return Routes.ventas;
    }
    if (hasPermission(role, AppPermission.viewCatalog)) {
      return Routes.catalogo;
    }

    return Routes.profile;
  }
}
