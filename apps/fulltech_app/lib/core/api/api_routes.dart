/// Centraliza rutas de API para fácil ajuste
class ApiRoutes {
  static const login = '/auth/login';
  static const refresh = '/auth/refresh';
  static const me = '/auth/me';

  // Usuarios
  static const users = '/users';
  static String userDetail(String id) => '/users/$id';
  static String updateUser(String id) => '/users/$id';
  static String deleteUser(String id) => '/users/$id';
  static String blockUser(String id) => '/users/$id/block';
  static String unblockUser(String id) => '/users/$id/unblock';

  // Ponche
  static const punchIn = '/punch/in';
  static const punchOut = '/punch/out';
  static const punchHistory = '/punch/history';

  // Ventas
  static const sales = '/sales';
  static const saleItems = '/sale_items';

  // Contabilidad
  static const ledger = '/ledger';
}
