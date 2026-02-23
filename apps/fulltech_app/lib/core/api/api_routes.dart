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
  static const punch = '/punch';
  static const punchMe = '/punch/me';
  static const punchAdmin = '/admin/punch';
  static const punchAttendanceSummary = '/admin/attendance/summary';
  static String punchAttendanceUser(String id) => '/admin/attendance/user/$id';

  // Contabilidad
  static const contabilidadCloses = '/contabilidad/closes';
  static String contabilidadCloseDetail(String id) => '/contabilidad/closes/$id';

  // Clientes
  static const clients = '/clients';
  static String clientDetail(String id) => '/clients/$id';

  // Productos
  static const products = '/products';
  static const productsUpload = '/products/upload';
  static String productDetail(String id) => '/products/$id';
  static String updateProduct(String id) => '/products/$id';
  static String deleteProduct(String id) => '/products/$id';
}
